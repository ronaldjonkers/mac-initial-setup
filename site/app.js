const catalogGrid = document.querySelector('#catalog-grid');
const categoryRail = document.querySelector('#category-rail');
const searchInput = document.querySelector('#catalog-search');
const resultCount = document.querySelector('#result-count');
let catalog = [];
let activeCategory = 'All';
let activeFilter = 'all';

const categoryIcons = {
  Core: '🍺', Browsers: '🌐', '1Password': '🔐', SSH: '🔑', Communication: '💬',
  'Remote access': '🖥️', Productivity: '⚡', Editors: '📝', 'AI apps': '🤖',
  'Terminal tools': '⌨️', 'Programming languages': '🧑‍💻', 'Developer tools': '🛠️',
  Finder: '🗂️', 'Dock & desktop': '⚓', 'Keyboard & trackpad': '⌨️',
  Screenshots: '📸', Safari: '🧭', 'System & security': '🛡️'
};

function itemCard(item) {
  const card = document.createElement('article');
  card.className = `catalog-item${item.kind === 'setting' ? ' setting-card' : item.on ? '' : ' optional'}`;
  const icon = document.createElement('div');
  icon.className = 'catalog-icon';
  icon.setAttribute('aria-hidden', 'true');
  icon.textContent = categoryIcons[item.category] || '✳';
  const text = document.createElement('div');
  const title = document.createElement('h3');
  title.textContent = item.label;
  const desc = document.createElement('p');
  desc.textContent = item.kind === 'setting' ? (item.value ? `Default: ${item.value}` : 'Fill in your own value') : (item.desc || item.category);
  const status = document.createElement('small');
  status.textContent = item.kind === 'setting' ? '✎ EDITABLE SETTING' : item.on ? '● ON BY DEFAULT' : '○ OPTIONAL';
  text.append(title, desc, status);
  card.append(icon, text);
  return card;
}

function renderCatalog() {
  const query = searchInput.value.trim().toLowerCase();
  const shown = catalog.filter(item =>
    (activeCategory === 'All' || item.category === activeCategory) &&
    (activeFilter === 'all' || (item.kind === 'item' && (activeFilter === 'on' ? item.on : !item.on))) &&
    `${item.label} ${item.desc} ${item.id} ${item.category}`.toLowerCase().includes(query)
  );
  resultCount.textContent = `${shown.length} ${shown.length === 1 ? 'item' : 'items'} shown`;
  catalogGrid.replaceChildren(...shown.map(itemCard));
  if (!shown.length) {
    const empty = document.createElement('p');
    empty.className = 'catalog-empty';
    empty.textContent = 'Nothing matches. Try another search or category.';
    catalogGrid.append(empty);
  }
}

function renderCategories() {
  const categories = ['All', ...new Set(catalog.map(item => item.category))];
  for (const category of categories) {
    const button = document.createElement('button');
    button.className = `category-button${category === activeCategory ? ' active' : ''}`;
    button.type = 'button';
    button.textContent = `${categoryIcons[category] || '✳'} ${category}`;
    button.setAttribute('aria-pressed', String(category === activeCategory));
    button.addEventListener('click', () => {
      activeCategory = category;
      for (const other of categoryRail.children) {
        const selected = other === button;
        other.classList.toggle('active', selected);
        other.setAttribute('aria-pressed', String(selected));
      }
      renderCatalog();
    });
    categoryRail.append(button);
  }
}

fetch('catalog.json')
  .then(response => { if (!response.ok) throw new Error('Catalog unavailable'); return response.json(); })
  .then(rows => {
    let category = '';
    catalog = rows.flatMap(row => {
      if (row.kind === 'section') { category = row.title; return []; }
      return row.kind === 'item' || row.kind === 'setting' ? [{ ...row, id: row.id || row.key, category }] : [];
    });
    const items = catalog.filter(item => item.kind === 'item');
    const selected = items.filter(item => item.on).length;
    document.querySelector('#catalog-count').textContent = `${items.length} choices (${selected} on by default) and ${catalog.length - items.length} editable settings`;
    renderCategories();
    renderCatalog();
  })
  .catch(() => { resultCount.textContent = 'Catalog unavailable'; catalogGrid.textContent = 'Browse the current list on GitHub.'; });

searchInput.addEventListener('input', renderCatalog);
document.querySelectorAll('.filter').forEach(button => button.addEventListener('click', () => {
  activeFilter = button.dataset.filter;
  document.querySelectorAll('.filter').forEach(other => {
    const selected = other === button;
    other.classList.toggle('active', selected);
    other.setAttribute('aria-pressed', String(selected));
  });
  renderCatalog();
}));

document.querySelectorAll('[data-copy]').forEach(button => button.addEventListener('click', async () => {
  const source = document.getElementById(button.dataset.copy);
  const value = source.textContent.trim();
  try {
    await navigator.clipboard.writeText(value);
  } catch {
    const helper = document.createElement('textarea');
    helper.value = value;
    helper.style.position = 'fixed';
    helper.style.opacity = '0';
    document.body.append(helper);
    helper.select();
    document.execCommand('copy');
    helper.remove();
  }
  const original = button.innerHTML;
  button.textContent = 'Copied ✓';
  setTimeout(() => { button.innerHTML = original; }, 1800);
}));

const progress = document.querySelector('#progress');
function updateProgress() {
  const height = document.documentElement.scrollHeight - window.innerHeight;
  progress.style.width = `${height > 0 ? window.scrollY / height * 100 : 0}%`;
}
window.addEventListener('scroll', updateProgress, { passive: true });
updateProgress();

if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) { entry.target.classList.add('visible'); observer.unobserve(entry.target); }
    });
  }, { threshold: .08 });
  document.querySelectorAll('.reveal').forEach(element => observer.observe(element));
} else {
  document.querySelectorAll('.reveal').forEach(element => element.classList.add('visible'));
}
