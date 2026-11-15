import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { badRequest, forbidden, HttpError } from '../errors.js';
import { isPremiumActive } from '../matchmaking/compat.js';
import { RATE_RULES } from '../services/rateLimit.js';
import { toWirePreferences, toWireUser } from '../services/serialize.js';
import {
  ChildrenSchema,
  DrinkingSchema,
  EducationSchema,
  GenderSchema,
  IntentionSchema,
  PreferencesInputSchema,
  ReligionSchema,
  SmokingSchema,
  type Preferences,
  type UserPatch,
} from '../types.js';
import { ageFromBirthdate, isValidBirthdate, iso, newId } from '../util.js';
import { decodeJpeg, parse } from './helpers.js';

export const MAX_PHOTOS = 6;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

const ProfileBody = z.object({
  firstName: z.string().trim().min(1).max(40).optional(),
  birthdate: z.string().refine(isValidBirthdate, 'must be a real date in YYYY-MM-DD form').optional(),
  gender: GenderSchema.optional(),
  interestedIn: z
    .array(GenderSchema)
    .min(1)
    .max(3)
    .transform((list) => [...new Set(list)])
    .optional(),
  bio: z.string().trim().max(500).optional(),
  city: z.string().trim().max(80).optional(),
  lat: z.number().min(-90).max(90).nullable().optional(),
  lng: z.number().min(-180).max(180).nullable().optional(),
  photoUrls: z.array(z.string().max(2048)).max(MAX_PHOTOS).optional(),
  intention: IntentionSchema.nullable().optional(),
  children: ChildrenSchema.nullable().optional(),
  religion: ReligionSchema.nullable().optional(),
  education: EducationSchema.nullable().optional(),
  smoking: SmokingSchema.nullable().optional(),
  drinking: DrinkingSchema.nullable().optional(),
  onboardingComplete: z.boolean().optional(),
  tzOffsetMinutes: z.number().int().min(-840).max(840).optional(),
});

const PhotoBody = z.object({ imageBase64: z.string().min(1) });
const PushTokenBody = z.object({
  apnsToken: z
    .string()
    .trim()
    .max(200)
    .regex(/^[0-9a-fA-F]*$/, 'must be a hex device token'),
  tzOffsetMinutes: z.number().int().min(-840).max(840),
  enabled: z.boolean(),
});

export function registerMeRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.get('/v1/me', async (request) => toWireUser(await ctx.authenticate(request), ctx.clock.now()));

  app.put('/v1/me', async (request) => {
    const user = await ctx.authenticate(request);
    const body = parse(ProfileBody, request.body);
    const now = ctx.clock.now();
    const patch: UserPatch = {};

    if (body.firstName !== undefined) patch.firstName = body.firstName;
    if (body.birthdate !== undefined && body.birthdate !== user.birthdate) {
      if (user.onboardingComplete && user.birthdate !== null) {
        throw badRequest('birthdate_locked', "Your date of birth can't be changed after sign-up.");
      }
      if (ageFromBirthdate(body.birthdate, now) < 18) {
        throw forbidden('underage', 'You need to be 18 or older to use this app.');
      }
      patch.birthdate = body.birthdate;
    }
    if (body.gender !== undefined) patch.gender = body.gender;
    if (body.interestedIn !== undefined) patch.interestedIn = body.interestedIn;
    if (body.bio !== undefined) patch.bio = body.bio;
    if (body.city !== undefined) patch.city = body.city;
    if (body.lat !== undefined || body.lng !== undefined) {
      const lat = body.lat === undefined ? user.lat : body.lat;
      const lng = body.lng === undefined ? user.lng : body.lng;
      if ((lat === null) !== (lng === null)) throw badRequest('invalid_request', 'lat and lng must be set together.');
      patch.lat = lat;
      patch.lng = lng;
    }
    let removedPhotos: string[] = [];
    if (body.photoUrls !== undefined) {
      // Only reordering or removing the user's own uploaded photos; new ones come from POST /v1/me/photos.
      const owned = new Set(user.photoUrls);
      const next = [...new Set(body.photoUrls)];
      if (!next.every((url) => owned.has(url))) {
        throw badRequest('invalid_photo', 'Photos must be uploaded before they can be added to your profile.');
      }
      removedPhotos = user.photoUrls.filter((url) => !next.includes(url));
      patch.photoUrls = next;
    }
    for (const key of ['intention', 'children', 'religion', 'education', 'smoking', 'drinking'] as const) {
      const value = body[key];
      if (value !== undefined) (patch as Record<string, unknown>)[key] = value;
    }
    if (body.tzOffsetMinutes !== undefined) patch.tzOffsetMinutes = body.tzOffsetMinutes;

    if (body.onboardingComplete === true && !user.onboardingComplete) {
      const merged = { ...user, ...patch };
      const complete =
        merged.firstName.trim().length > 0 &&
        merged.birthdate !== null &&
        merged.gender !== null &&
        merged.interestedIn.length > 0;
      if (!complete) {
        throw badRequest(
          'profile_incomplete',
          'Add your first name, date of birth, gender and who you want to meet to finish.',
        );
      }
      patch.onboardingComplete = true;
    }

    const updated = (await ctx.store.updateUser(user.id, patch)) ?? user;
    for (const url of removedPhotos) {
      await ctx.blobs.deleteByUrl(url).catch(() => undefined);
    }
    await ctx.queue.refresh(user.id);
    return toWireUser(updated, now);
  });

  app.put('/v1/me/preferences', async (request) => {
    const user = await ctx.authenticate(request);
    const body = parse(PreferencesInputSchema, request.body);
    const stored = user.preferences;
    const next: Preferences = {
      ageMin: body.ageMin,
      ageMax: body.ageMax,
      maxDistanceKm: body.maxDistanceKm,
      notifyOnlineSingles: body.notifyOnlineSingles,
    };
    if (isPremiumActive(user, ctx.clock.now())) {
      // PUT replaces: an advanced filter that is absent, null or empty is cleared.
      if (body.intentions && body.intentions.length > 0) next.intentions = body.intentions;
      if (body.children && body.children.length > 0) next.children = body.children;
      if (body.religions && body.religions.length > 0) next.religions = body.religions;
      if (body.minEducation) next.minEducation = body.minEducation;
      if (body.smokingOk && body.smokingOk.length > 0) next.smokingOk = body.smokingOk;
      if (body.drinkingOk && body.drinkingOk.length > 0) next.drinkingOk = body.drinkingOk;
    } else {
      // Not premium: advanced fields in the request are ignored; whatever was stored is kept untouched.
      if (stored.intentions) next.intentions = stored.intentions;
      if (stored.children) next.children = stored.children;
      if (stored.religions) next.religions = stored.religions;
      if (stored.minEducation) next.minEducation = stored.minEducation;
      if (stored.smokingOk) next.smokingOk = stored.smokingOk;
      if (stored.drinkingOk) next.drinkingOk = stored.drinkingOk;
    }
    const updated = await ctx.store.updateUser(user.id, { preferences: next });
    await ctx.queue.refresh(user.id);
    return toWirePreferences(updated?.preferences ?? next);
  });

  app.post('/v1/me/photos', { bodyLimit: 8 * 1024 * 1024 }, async (request) => {
    const user = await ctx.authenticate(request);
    ctx.rateLimiter.enforce(RATE_RULES.photo, user.id);
    const body = parse(PhotoBody, request.body);
    if (user.photoUrls.length >= MAX_PHOTOS) {
      throw badRequest('too_many_photos', `You can have up to ${MAX_PHOTOS} photos. Remove one first.`);
    }
    const jpeg = decodeJpeg(body.imageBase64, MAX_PHOTO_BYTES);
    if (!(await ctx.moderation.screenPhoto(user.id, jpeg))) {
      throw new HttpError(422, 'photo_rejected', "That photo can't be used. Choose one without nudity.");
    }
    const url = await ctx.blobs.put(`${newId()}.jpg`, jpeg, 'image/jpeg');
    // Re-read so two parallel uploads do not overwrite each other's entry.
    const fresh = (await ctx.store.getUser(user.id)) ?? user;
    await ctx.store.updateUser(user.id, { photoUrls: [...fresh.photoUrls, url].slice(0, MAX_PHOTOS) });
    await ctx.queue.refresh(user.id);
    return { url };
  });

  app.post('/v1/me/push-token', async (request, reply) => {
    const user = await ctx.authenticate(request);
    const body = parse(PushTokenBody, request.body);
    const token = body.apnsToken.length > 0 ? body.apnsToken.toLowerCase() : null;
    await ctx.store.updateUser(user.id, {
      apnsToken: token,
      pushEnabled: body.enabled && token !== null,
      tzOffsetMinutes: body.tzOffsetMinutes,
    });
    return reply.code(204).send();
  });

  app.delete('/v1/me', async (request, reply) => {
    const user = await ctx.authenticate(request);
    await ctx.accounts.deleteAccount(user);
    return reply.code(204).send();
  });

  app.get('/v1/usage', async (request) => {
    const user = await ctx.authenticate(request);
    const usage = await ctx.usage.get(user);
    return { datesToday: usage.datesToday, limit: usage.limit, resetsAt: iso(usage.resetsAt) };
  });

  app.get('/v1/online-count', async (request) => {
    const user = await ctx.authenticate(request);
    const candidate = user.onboardingComplete ? await ctx.queue.buildCandidate(user) : null;
    return {
      compatibleOnline: candidate ? ctx.matchmaker.compatibleOnline(candidate, ctx.clock.now()) : 0,
    };
  });
}
