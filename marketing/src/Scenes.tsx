import React from 'react';
import {AbsoluteFill, useCurrentFrame, useVideoConfig} from 'remotion';
import {loadFonts} from './fonts';
import {T, TAU} from './theme';
import {Paper, Washes, WashSpec} from './Watercolor';

loadFonts();

// Everything below is periodic in `p` (0 → 1 over the clip), so every clip loops seamlessly.
const useLoop = () => {
  const frame = useCurrentFrame();
  const {durationInFrames, width, height} = useVideoConfig();
  return {p: frame / durationInFrames, width, height};
};
const wave = (p: number, cycles = 1, phase = 0) => Math.sin(TAU * (cycles * p + phase));

const drift = (base: WashSpec, p: number, phase: number, amount = 1): WashSpec => ({
  ...base,
  x: base.x + wave(p, 1, phase) * base.r * 0.07 * amount,
  y: base.y + wave(p, 1, phase + 0.25) * base.r * 0.06 * amount,
  r: base.r * (1 + wave(p, 1, phase + 0.5) * 0.05 * amount),
  wobble: base.r * (0.42 + wave(p, 2, phase) * 0.05 * amount),
  rotate: (base.rotate ?? 0) + wave(p, 1, phase) * 4 * amount,
});

const Eyebrow: React.FC<{children: React.ReactNode; size?: number}> = ({children, size = 15}) => (
  <div style={{fontFamily: T.sans, fontWeight: 600, fontSize: size, letterSpacing: size * 0.07, textTransform: 'uppercase', color: T.ink2}}>
    {children}
  </div>
);

// 1. Hero: washes breathing behind the headline.
export const HeroWash: React.FC<{showText?: boolean}> = ({showText = true}) => {
  const {p, width, height} = useLoop();
  const u = width / 1200;
  const washes: WashSpec[] = [
    drift({x: 880 * u, y: 250 * u, r: 250 * u, color: T.blush, seed: 3, squash: 0.86, rotate: -12}, p, 0),
    drift({x: 1040 * u, y: 430 * u, r: 190 * u, color: T.butter, seed: 11, squash: 0.92}, p, 0.3),
    drift({x: 740 * u, y: 470 * u, r: 170 * u, color: T.sage, seed: 21, squash: 0.8, rotate: 20}, p, 0.55),
    drift({x: 930 * u, y: 330 * u, r: 92 * u, color: T.accent, seed: 31, opacity: 0.8}, p, 0.75, 1.4),
    drift({x: 1130 * u, y: 170 * u, r: 80 * u, color: T.lilac, seed: 41}, p, 0.15, 1.3),
    drift({x: 150 * u, y: 620 * u, r: 130 * u, color: T.sky, seed: 51, opacity: 0.6, squash: 0.7}, p, 0.9),
  ];
  return (
    <AbsoluteFill>
      <Paper width={width} height={height} />
      <Washes washes={washes} width={width} height={height} />
      {showText ? (
        <AbsoluteFill style={{padding: `${96 * u}px ${88 * u}px`, justifyContent: 'center'}}>
          <Eyebrow size={15 * u}>Live video speed dating</Eyebrow>
          <div style={{fontFamily: T.serif, fontWeight: 500, fontSize: 92 * u, lineHeight: 1.02, letterSpacing: -2.2 * u, color: T.ink, marginTop: 22 * u, maxWidth: 640 * u}}>
            Four minutes.
            <br />
            Face to <span style={{fontStyle: 'italic'}}>face.</span>
          </div>
          <div style={{fontFamily: T.sans, fontSize: 24 * u, lineHeight: 1.4, color: T.ink2, marginTop: 28 * u, maxWidth: 470 * u}}>
            Go online, meet someone who is online right now, and decide together.
          </div>
        </AbsoluteFill>
      ) : null}
    </AbsoluteFill>
  );
};

// 2. Go online: the Pulse button on a soft bloom.
export const GoOnline: React.FC = () => {
  const {p, width, height} = useLoop();
  const c = width / 2;
  const cy = height * 0.47;
  const u = width / 640;
  const breathe = 1 + wave(p, 2) * 0.025;
  const washes: WashSpec[] = [
    drift({x: c - 40 * u, y: cy + 10 * u, r: 215 * u, color: T.blush, seed: 5, opacity: 0.75}, p, 0),
    drift({x: c + 90 * u, y: cy - 60 * u, r: 130 * u, color: T.butter, seed: 15, opacity: 0.8}, p, 0.4, 1.3),
    drift({x: c + 60 * u, y: cy + 110 * u, r: 110 * u, color: T.lilac, seed: 25, opacity: 0.7}, p, 0.7, 1.3),
  ];
  const ripples = [0, 1 / 3, 2 / 3].map((o) => (p * 2 + o) % 1);
  return (
    <AbsoluteFill>
      <Paper width={width} height={height} />
      <Washes washes={washes} width={width} height={height} />
      <svg width={width} height={height} style={{position: 'absolute', inset: 0}}>
        {ripples.map((r, i) => (
          <circle key={i} cx={c} cy={cy} r={(150 + r * 120) * u} fill="none" stroke={T.ink} strokeWidth={1.2 * u} opacity={0.22 * (1 - r)} />
        ))}
        <circle cx={c} cy={cy} r={148 * u * breathe} fill={T.white} opacity={0.9} />
        <circle cx={c} cy={cy} r={148 * u * breathe} fill="none" stroke={T.accent} strokeWidth={3 * u} />
      </svg>
      <AbsoluteFill style={{alignItems: 'center'}}>
        <div style={{position: 'absolute', top: cy - 30 * u, fontFamily: T.serif, fontWeight: 500, fontSize: 46 * u, letterSpacing: -1 * u, color: T.ink}}>Go online</div>
        <div style={{position: 'absolute', top: height * 0.86, display: 'flex', alignItems: 'center', gap: 10 * u, fontFamily: T.sans, fontSize: 21 * u, color: T.ink2}}>
          <div style={{width: 10 * u, height: 10 * u, borderRadius: 99, background: T.yes, opacity: 0.55 + 0.45 * (0.5 + 0.5 * wave(p, 4))}} />
          23 compatible people online now
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// 3. The Turn Card: the chess-clock icebreaker.
export const TurnCard: React.FC = () => {
  const {p, width, height} = useLoop();
  const u = width / 640;
  const myTurn = p < 0.5;
  const local = myTurn ? p / 0.5 : (p - 0.5) / 0.5; // 0 → 1 within a turn
  const remaining = 1 - local;
  const swap = Math.min(1, Math.min(local, 1 - local) / 0.06); // quick fade at each hand-over
  const seconds = Math.max(0, Math.ceil(remaining * 30));
  const washes: WashSpec[] = [
    drift({x: 170 * u, y: 170 * u, r: 190 * u, color: T.sage, seed: 8, opacity: 0.75}, p, 0.1),
    drift({x: 500 * u, y: 470 * u, r: 200 * u, color: T.blush, seed: 18, opacity: 0.75}, p, 0.5),
    drift({x: 520 * u, y: 150 * u, r: 90 * u, color: T.butter, seed: 28}, p, 0.8, 1.4),
  ];
  const half = (active: boolean, name: string, align: 'flex-start' | 'flex-end') => (
    <div style={{flex: 1, display: 'flex', flexDirection: 'column', alignItems: align, gap: 9 * u}}>
      <div style={{width: '100%', height: 8 * u, borderRadius: 99, background: T.surface2, overflow: 'hidden', display: 'flex', justifyContent: align}}>
        <div style={{width: `${active ? remaining * 100 : 0}%`, height: '100%', borderRadius: 99, background: T.accent}} />
      </div>
      <div style={{fontFamily: T.sans, fontSize: 17 * u, fontWeight: active ? 600 : 400, color: active ? T.ink : T.ink2}}>{name}</div>
    </div>
  );
  return (
    <AbsoluteFill>
      <Paper width={width} height={height} />
      <Washes washes={washes} width={width} height={height} />
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
        <div style={{width: 520 * u, background: T.white, borderRadius: 22 * u, border: `1px solid ${T.hair}`, boxShadow: `0 ${10 * u}px ${30 * u}px rgba(27,23,25,0.08)`, padding: 34 * u, display: 'flex', flexDirection: 'column', gap: 18 * u}}>
          <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
            <Eyebrow size={14 * u}>Question 3</Eyebrow>
            <div style={{fontFamily: T.sans, fontWeight: 600, fontSize: 19 * u, color: T.ink, fontVariantNumeric: 'tabular-nums'}}>0:{String(seconds).padStart(2, '0')}</div>
          </div>
          <div style={{fontFamily: T.serif, fontWeight: 500, fontSize: 40 * u, lineHeight: 1.12, letterSpacing: -0.8 * u, color: T.ink}}>
            What is a small thing that made this week better?
          </div>
          <div style={{display: 'flex', gap: 10 * u, marginTop: 10 * u}}>
            {half(myTurn, 'You', 'flex-start')}
            {half(!myTurn, 'Maya', 'flex-end')}
          </div>
          <div style={{height: 54 * u, display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 4 * u}}>
            {myTurn ? (
              <div style={{opacity: swap, height: 54 * u, padding: `0 ${44 * u}px`, borderRadius: 99, background: T.ink, color: T.white, fontFamily: T.sans, fontWeight: 600, fontSize: 19 * u, display: 'flex', alignItems: 'center'}}>Pass</div>
            ) : (
              <div style={{opacity: swap, fontFamily: T.sans, fontSize: 18 * u, color: T.ink2}}>Maya is answering</div>
            )}
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// 4. It's mutual: two washes meeting inside interlocked rings.
export const Mutual: React.FC = () => {
  const {p, width, height} = useLoop();
  const u = width / 640;
  const c = width / 2;
  const cy = height * 0.4;
  const gap = (58 + wave(p, 1, 0.75) * 16) * u; // the two drift together and ease apart
  const washes: WashSpec[] = [
    drift({x: c - gap, y: cy, r: 128 * u, color: T.blush, seed: 6, wobble: 30 * u}, p, 0),
    drift({x: c + gap, y: cy, r: 128 * u, color: T.sage, seed: 16, wobble: 30 * u}, p, 0.5),
    drift({x: c, y: cy + 128 * u, r: 56 * u, color: T.butter, seed: 26, opacity: 0.7}, p, 0.3, 1.5),
  ];
  return (
    <AbsoluteFill>
      <Paper width={width} height={height} />
      <Washes washes={washes} width={width} height={height} />
      <svg width={width} height={height} style={{position: 'absolute', inset: 0}}>
        <circle cx={c - gap} cy={cy} r={112 * u} fill="none" stroke={T.accent} strokeWidth={2.5 * u} />
        <circle cx={c + gap} cy={cy} r={112 * u} fill="none" stroke={T.ink} strokeWidth={2.5 * u} />
      </svg>
      <AbsoluteFill style={{alignItems: 'center'}}>
        <div style={{position: 'absolute', top: height * 0.72, fontFamily: T.serif, fontWeight: 500, fontSize: 68 * u, letterSpacing: -1.6 * u, color: T.ink}}>
          It&rsquo;s <span style={{fontStyle: 'italic'}}>mutual.</span>
        </div>
        <div style={{position: 'absolute', top: height * 0.88, fontFamily: T.sans, fontSize: 21 * u, color: T.ink2}}>You both said yes.</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
