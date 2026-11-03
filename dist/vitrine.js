const showcase = document.querySelector('.brand-carousel');
const track = showcase.querySelector('.brand-grid');
const controls = showcase.querySelector('.carousel-controls');
const toggle = controls.querySelector('[data-toggle]');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const smallScreen = window.matchMedia('(max-width: 759px)');
let paused = reducedMotion.matches || smallScreen.matches;
let pointerInside = false;
let timer;

function move(direction) {
  const cards = Array.from(track.children);
  const origin = cards[0].offsetLeft;
  const limit = track.scrollWidth - track.clientWidth;
  const stops = [...new Set(cards.map(card => Math.min(limit, card.offsetLeft - origin)))];
  const current = stops.reduce((best, stop, index) =>
    Math.abs(stop - track.scrollLeft) < Math.abs(stops[best] - track.scrollLeft) ? index : best, 0);
  const next = (current + direction + stops.length) % stops.length;
  track.scrollTo({ left: stops[next], behavior: reducedMotion.matches || smallScreen.matches ? 'instant' : 'smooth' });
}

function schedule() {
  window.clearInterval(timer);
  toggle.textContent = paused ? 'Reproduzir' : 'Pausar';
  if (!paused && !pointerInside && !showcase.contains(document.activeElement) && !document.hidden) {
    timer = window.setInterval(() => move(1), 6500);
  }
}

controls.querySelector('[data-prev]').addEventListener('click', () => move(-1));
controls.querySelector('[data-next]').addEventListener('click', () => move(1));
track.addEventListener('keydown', event => {
  if (event.target !== track) return;
  if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') {
    event.preventDefault();
    move(event.key === 'ArrowRight' ? 1 : -1);
  }
});
toggle.addEventListener('click', () => {
  paused = !paused;
  schedule();
});
showcase.addEventListener('pointerenter', () => { pointerInside = true; schedule(); });
showcase.addEventListener('pointerleave', () => { pointerInside = false; schedule(); });
showcase.addEventListener('focusin', schedule);
showcase.addEventListener('focusout', () => window.setTimeout(schedule, 0));
document.addEventListener('visibilitychange', schedule);
reducedMotion.addEventListener('change', () => { paused = reducedMotion.matches || smallScreen.matches; schedule(); });
smallScreen.addEventListener('change', () => { paused = reducedMotion.matches || smallScreen.matches; schedule(); });
controls.hidden = false;
schedule();
