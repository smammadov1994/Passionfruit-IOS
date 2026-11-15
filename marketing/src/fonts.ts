import {continueRender, delayRender, staticFile} from 'remotion';

let started = false;
export const loadFonts = () => {
  if (started || typeof document === 'undefined') return;
  started = true;
  const handle = delayRender('fonts');
  const faces = [
    new FontFace('Newsreader', `url(${staticFile('newsreader-latin-500-normal.woff2')})`, {weight: '500', style: 'normal'}),
    new FontFace('Newsreader', `url(${staticFile('newsreader-latin-500-italic.woff2')})`, {weight: '500', style: 'italic'}),
  ];
  Promise.all(faces.map((f) => f.load()))
    .then((loaded) => {
      loaded.forEach((f) => document.fonts.add(f));
      continueRender(handle);
    })
    .catch(() => continueRender(handle));
};
