/* Tokyo Zero MISC — Shopify front-end JS
   Handles three things:
   1. Catalog filter chips + search input → hide tiles/sections
   2. Cart drawer open/close (link with [data-cart-toggle] and overlay)
   3. Cart line-item quantity controls (Shopify /cart/change.js) + re-render */

(function () {
  /* ===== Page-load transition ===== */
  /* Fade + lift the misc/collection pages in once the DOM is parsed.
     CSS handles the actual transition; this just toggles the class. */
  function markLoaded () {
    document.body.classList.add('is-loaded');
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', markLoaded);
  } else {
    markLoaded();
  }

  /* ===== Catalog filter + search ===== */
  const chips    = document.querySelectorAll('.misc__chip');
  const input    = document.querySelector('.misc__search-input');
  const cards    = document.querySelectorAll('.misc__card');
  const sections = document.querySelectorAll('.misc__section');
  const emptyMsg = document.querySelector('.misc__empty--results');
  let activeFilter = 'all';

  function applyFilter() {
    const q = (input?.value || '').trim().toLowerCase();
    let anyVisible = false;
    cards.forEach(c => {
      const cat = c.getAttribute('data-category');
      const hay = c.getAttribute('data-search') || '';
      const hitCat = (activeFilter === 'all' || cat === activeFilter);
      const hitQ   = (!q || hay.indexOf(q) !== -1);
      const show = hitCat && hitQ;
      c.hidden = !show;
      if (show) anyVisible = true;
    });
    sections.forEach(s => {
      const visible = s.querySelectorAll('.misc__card:not([hidden])').length;
      s.hidden = visible === 0;
    });
    if (emptyMsg) emptyMsg.hidden = anyVisible;
  }

  chips.forEach(chip => {
    chip.addEventListener('click', () => {
      chips.forEach(c => c.classList.remove('is-active'));
      chip.classList.add('is-active');
      activeFilter = chip.getAttribute('data-filter') || 'all';
      applyFilter();
    });
  });

  if (input) {
    let t;
    input.addEventListener('input', () => {
      clearTimeout(t);
      t = setTimeout(applyFilter, 80);
    });
  }

  /* ===== Cart drawer ===== */
  const drawer = document.querySelector('[data-cart-drawer]');
  const drawerItems = document.querySelector('[data-cart-items]');
  const subtotalEl  = document.querySelector('[data-cart-subtotal]');
  const cartCount   = document.querySelector('[data-cart-count]');

  function openDrawer() {
    if (!drawer) return;
    drawer.hidden = false;
    drawer.setAttribute('aria-hidden', 'false');
    document.body.style.overflow = 'hidden';
  }
  function closeDrawer() {
    if (!drawer) return;
    drawer.hidden = true;
    drawer.setAttribute('aria-hidden', 'true');
    document.body.style.overflow = '';
  }
  document.querySelectorAll('[data-cart-toggle]').forEach(b => b.addEventListener('click', e => { e.preventDefault(); openDrawer(); }));
  document.querySelectorAll('[data-cart-close]').forEach(b => b.addEventListener('click', closeDrawer));
  document.body.addEventListener('cart:open', openDrawer);

  /* Listen for the form submission on the product page so the cart drawer
     opens right after Add to Cart instead of jumping to /cart. */
  document.querySelectorAll('form[action*="/cart/add"]').forEach(f => {
    f.addEventListener('submit', async (e) => {
      e.preventDefault();
      const fd = new FormData(f);
      try {
        await fetch('/cart/add.js', { method: 'POST', body: fd, headers: { 'Accept': 'application/json' } });
        await refreshCart();
        openDrawer();
      } catch (err) {
        f.submit();  /* fallback: native submit */
      }
    });
  });

  /* Qty +/- inside the drawer */
  document.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-qty-delta]');
    if (!btn) return;
    e.preventDefault();
    const key = btn.getAttribute('data-key');
    const delta = parseInt(btn.getAttribute('data-qty-delta'), 10);
    const item = btn.closest('.cart-drawer__item');
    const cur = parseInt(item.querySelector('.cart-drawer__qty-num').textContent, 10) || 0;
    const newQty = Math.max(0, cur + delta);
    try {
      await fetch('/cart/change.js', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ id: key, quantity: newQty }),
      });
      await refreshCart();
    } catch (err) { /* ignore */ }
  });

  /* Pull the latest cart and re-render drawer + count badge. */
  async function refreshCart() {
    try {
      const r = await fetch('/cart.js', { headers: { 'Accept': 'application/json' } });
      const cart = await r.json();
      if (cartCount)  cartCount.textContent = cart.item_count;
      if (subtotalEl) subtotalEl.textContent = money(cart.total_price);
      if (drawerItems) {
        if (cart.item_count === 0) {
          drawerItems.innerHTML = '<p class="cart-drawer__empty">Your cart is empty.</p>';
          return;
        }
        drawerItems.innerHTML = cart.items.map(it => `
          <article class="cart-drawer__item" data-key="${it.key}">
            <a class="cart-drawer__thumb" href="${it.url}">
              ${it.image ? `<img src="${it.image}" alt="${escapeHtml(it.title)}">` : ''}
            </a>
            <div class="cart-drawer__info">
              <p class="cart-drawer__name"><a href="${it.url}">${escapeHtml(it.product_title)}</a></p>
              <div class="cart-drawer__qty">
                <button type="button" class="cart-drawer__qty-btn" data-qty-delta="-1" data-key="${it.key}" aria-label="Decrease">−</button>
                <span class="cart-drawer__qty-num">${it.quantity}</span>
                <button type="button" class="cart-drawer__qty-btn" data-qty-delta="1"  data-key="${it.key}" aria-label="Increase">+</button>
              </div>
            </div>
            <div class="cart-drawer__price">${money(it.final_line_price)}</div>
          </article>
        `).join('');
      }
    } catch (err) { /* ignore */ }
  }

  function money(cents) {
    /* Shopify cents → USD-ish — replace with proper Shopify.formatMoney if needed */
    return '$' + (cents / 100).toFixed(2);
  }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  }

  window.addEventListener('wheel', function (e) {
    if (e.ctrlKey || e.metaKey) { e.preventDefault(); }
  }, { passive: false });
  window.addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && ['+', '-', '=', '0'].indexOf(e.key) !== -1) {
      e.preventDefault();
    }
  });
  document.addEventListener('gesturestart',  function (e) { e.preventDefault(); });
  document.addEventListener('gesturechange', function (e) { e.preventDefault(); });
  document.addEventListener('gestureend',    function (e) { e.preventDefault(); });
})();
