import React from 'react';
import {Composition} from 'remotion';
import {GoOnline, HeroWash, Mutual, TurnCard} from './Scenes';

const FPS = 30;
export const Root: React.FC = () => (
  <>
    <Composition id="HeroWash" component={HeroWash} width={1200} height={675} fps={FPS} durationInFrames={FPS * 6} defaultProps={{showText: true}} />
    <Composition id="HeroBackground" component={HeroWash} width={1200} height={675} fps={FPS} durationInFrames={FPS * 6} defaultProps={{showText: false}} />
    <Composition id="GoOnline" component={GoOnline} width={640} height={640} fps={FPS} durationInFrames={FPS * 4} />
    <Composition id="TurnCard" component={TurnCard} width={640} height={640} fps={FPS} durationInFrames={FPS * 6} />
    <Composition id="Mutual" component={Mutual} width={640} height={640} fps={FPS} durationInFrames={FPS * 5} />
  </>
);
