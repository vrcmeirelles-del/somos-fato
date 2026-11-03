const menu = document.querySelector('.menu-button');
const mobileNav = document.querySelector('.mobile-nav');
const desktop = window.matchMedia('(min-width: 1100px)');

function closeMenu(restoreFocus = false) {
  menu.setAttribute('aria-expanded', 'false');
  mobileNav.classList.remove('open');
  if (restoreFocus) menu.focus();
}

menu.addEventListener('click', () => {
  const open = menu.getAttribute('aria-expanded') !== 'true';
  menu.setAttribute('aria-expanded', String(open));
  mobileNav.classList.toggle('open', open);
});
mobileNav.querySelectorAll('a').forEach(link => link.addEventListener('click', () => {
  closeMenu();
  const target = document.querySelector(link.hash);
  if (target) {
    target.setAttribute('tabindex', '-1');
    target.focus({ preventScroll: true });
  }
}));
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && menu.getAttribute('aria-expanded') === 'true') closeMenu(true);
});
document.addEventListener('click', event => {
  if (!event.target.closest('.header')) closeMenu();
});
desktop.addEventListener('change', () => closeMenu());

document.getElementById('year').textContent = new Date().getFullYear();
const privacy = document.getElementById('privacy-dialog');
document.getElementById('privacy-open').addEventListener('click', () => privacy.showModal());
