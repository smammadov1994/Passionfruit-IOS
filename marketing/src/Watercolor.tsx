import React from 'react';
import {AbsoluteFill} from 'remotion';
import {T} from './theme';

export type WashSpec = {
  x: number; // centre, px
  y: number;
  r: number; // radius, px
  color: string;
  seed: number;
  opacity?: number;
  wobble?: number; // displacement strength, px
  squash?: number; // ry / rx
  rotate?: number; // degrees
};

// One watercolour wash: a soft disc whose edge is torn by fractal noise,
// with pigment pooling toward the rim and a granulation pass on top.
const Wash: React.FC<{w: WashSpec; id: string}> = ({w, id}) => {
  const wobble = w.wobble ?? w.r * 0.42;
  return (
    <g style={{mixBlendMode: 'multiply'}} opacity={w.opacity ?? 0.85}>
      <defs>
        <radialGradient id={`${id}-g`}>
          <stop offset="0" stopColor={w.color} stopOpacity={0.3} />
          <stop offset="0.55" stopColor={w.color} stopOpacity={0.42} />
          <stop offset="0.86" stopColor={w.color} stopOpacity={0.62} />
          <stop offset="0.97" stopColor={w.color} stopOpacity={0.95} />
          <stop offset="1" stopColor={w.color} stopOpacity={0} />
        </radialGradient>
        <filter id={`${id}-f`} x="-60%" y="-60%" width="220%" height="220%" colorInterpolationFilters="sRGB">
          <feTurbulence type="fractalNoise" baseFrequency={0.0065} numOctaves={4} seed={w.seed} result="big" />
          <feDisplacementMap in="SourceGraphic" in2="big" scale={wobble} xChannelSelector="R" yChannelSelector="G" result="torn" />
          <feTurbulence type="fractalNoise" baseFrequency={0.035} numOctaves={2} seed={w.seed + 7} result="fine" />
          <feDisplacementMap in="torn" in2="fine" scale={w.r * 0.05} xChannelSelector="G" yChannelSelector="B" result="edge" />
          <feGaussianBlur in="edge" stdDeviation={1.1} result="soft" />
          <feTurbulence type="fractalNoise" baseFrequency={0.9} numOctaves={2} seed={w.seed + 13} result="grain" />
          <feColorMatrix in="grain" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0.9 0.9 0 0 0.25" result="grainA" />
          <feComposite in="soft" in2="grainA" operator="in" />
        </filter>
      </defs>
      <ellipse
        cx={w.x}
        cy={w.y}
        rx={w.r}
        ry={w.r * (w.squash ?? 1)}
        transform={`rotate(${w.rotate ?? 0} ${w.x} ${w.y})`}
        fill={`url(#${id}-g)`}
        filter={`url(#${id}-f)`}
      />
    </g>
  );
};

export const Washes: React.FC<{washes: WashSpec[]; width: number; height: number; idPrefix?: string}> = ({
  washes,
  width,
  height,
  idPrefix = 'w',
}) => (
  <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} style={{position: 'absolute', inset: 0}}>
    {washes.map((w, i) => (
      <Wash key={i} w={w} id={`${idPrefix}${i}`} />
    ))}
  </svg>
);

// Cold-pressed paper: a faint static tooth over everything.
export const Paper: React.FC<{width: number; height: number; background?: string}> = ({width, height, background}) => (
  <AbsoluteFill style={{backgroundColor: background ?? T.paper}}>
    <svg width={width} height={height} style={{position: 'absolute', inset: 0}}>
      <filter id="paper-tooth" x="0" y="0" width="100%" height="100%">
        <feTurbulence type="fractalNoise" baseFrequency={0.75} numOctaves={3} seed={4} />
        <feColorMatrix type="matrix" values="0 0 0 0 0.35  0 0 0 0 0.3  0 0 0 0 0.28  0.09 0.09 0 0 -0.02" />
      </filter>
      <rect width={width} height={height} filter="url(#paper-tooth)" />
    </svg>
  </AbsoluteFill>
);
