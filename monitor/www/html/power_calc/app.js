const presets = [
  { name: "LED light", category: "Lighting", watts: 10, surge: 1 },
  { name: "Refrigerator", category: "Kitchen", watts: 700, surge: 3 },
  { name: "Freezer", category: "Kitchen", watts: 500, surge: 3 },
  { name: "Fridge freezer", category: "Kitchen", watts: 600, surge: 3 },
  { name: "Window air conditioner", category: "Climate", watts: 1200, surge: 2.5 },
  { name: "Central AC (3 ton)", category: "Climate", watts: 3500, surge: 3 },
  { name: "Sump pump (1/2 hp)", category: "Pumps", watts: 1000, surge: 3 },
  { name: "Well pump (1 hp)", category: "Pumps", watts: 2000, surge: 3 },
  { name: "Microwave", category: "Kitchen", watts: 1000, surge: 1 },
  { name: "Coffee maker", category: "Kitchen", watts: 1000, surge: 1 },
  { name: "Television", category: "Electronics", watts: 150, surge: 1 },
  { name: "Wi-Fi router", category: "Electronics", watts: 15, surge: 1 },
  { name: "Laptop charger", category: "Electronics", watts: 90, surge: 1 },
  { name: "Washing machine", category: "Laundry", watts: 500, surge: 2 },
  { name: "Gas combi boiler", category: "Heating + hot water", watts: 150, surge: 2 },
  { name: "Electric water heater", category: "Heating", watts: 4500, surge: 1 },
  { name: "Electric space heater", category: "Heating", watts: 1500, surge: 1 },
  { name: "Garage door opener", category: "Workshop", watts: 550, surge: 3 },
  { name: "Circular saw", category: "Workshop", watts: 1400, surge: 3 },
];

const generatorSizes = [1000, 1500, 2000, 2500, 3000, 3500, 4000, 5000, 6000, 7000, 8000, 10000, 12000, 15000, 20000];
const storageKey = "wattwise-loads-v1";
const previousStorageKey = "wattwise-last-loads-v1";
const presetSelect = document.querySelector("#preset-select");
const loadList = document.querySelector("#load-list");
const emptyState = document.querySelector("#empty-state");
const customDialog = document.querySelector("#custom-dialog");
const customForm = document.querySelector("#custom-form");
let startupMode = "staggered";
let loads = loadSavedLoads();

try {
  if (loads.length && !localStorage.getItem(previousStorageKey)) {
    localStorage.setItem(previousStorageKey, JSON.stringify(loads));
  }
} catch {}

for (const [index, preset] of presets.entries()) {
  const option = document.createElement("option");
  option.value = String(index);
  option.textContent = `${preset.name} — ${preset.watts} W`;
  presetSelect.append(option);
}

function loadSavedLoads(key = storageKey) {
  try {
    const saved = JSON.parse(localStorage.getItem(key) || "[]");
    return Array.isArray(saved) ? saved.filter(isValidLoad) : [];
  } catch {
    return [];
  }
}

function isValidLoad(load) {
  return load && typeof load.name === "string" && Number.isFinite(Number(load.watts)) && Number(load.watts) > 0 && Number.isFinite(Number(load.surge)) && Number(load.surge) >= 1 && Number.isFinite(Number(load.quantity)) && Number(load.quantity) > 0;
}

function saveLoads() {
  const saved = JSON.stringify(loads);
  localStorage.setItem(storageKey, saved);
  if (loads.length) localStorage.setItem(previousStorageKey, saved);
}

function formatWatts(value) {
  return Math.round(value).toLocaleString("en-US");
}

function marketplaceSearchUrl(baseUrl, parameter, watts) {
  const url = new URL(baseUrl);
  url.searchParams.set(parameter, `portable generator ${Math.round(watts)}W rated output`);
  return url.toString();
}

function createNumberInput(label, value, min, max, step, onChange) {
  const input = document.createElement("input");
  input.className = "cell-input";
  input.type = "number";
  input.setAttribute("aria-label", label);
  input.min = String(min);
  input.max = String(max);
  input.step = String(step);
  input.value = String(value);
  input.addEventListener("change", () => {
    const next = Number(input.value);
    if (!Number.isFinite(next) || next < min || next > max) {
      input.value = String(value);
      return;
    }
    onChange(next);
  });
  return input;
}

function createRowAction(symbol, label, disabled, onClick) {
  const button = document.createElement("button");
  button.className = "row-action-button";
  button.type = "button";
  button.textContent = symbol;
  button.title = label;
  button.setAttribute("aria-label", label);
  button.disabled = disabled;
  button.addEventListener("click", onClick);
  return button;
}

function renderLoads() {
  loadList.replaceChildren();
  emptyState.hidden = loads.length > 0;
  document.querySelector("#reload-button").disabled = loadSavedLoads(previousStorageKey).length === 0;
  document.querySelector("#item-count").textContent = `${loads.length} ${loads.length === 1 ? "ITEM" : "ITEMS"}`;

  loads.forEach((load, index) => {
    const row = document.createElement("div");
    row.className = "load-row";

    const name = document.createElement("div");
    name.className = "load-name";
    name.title = load.name;
    name.append(document.createTextNode(load.name));
    const category = document.createElement("span");
    category.className = "load-category";
    category.textContent = load.category || "Custom load";
    name.append(category);

    const quantityInput = createNumberInput(`${load.name} quantity`, load.quantity, 1, 99, 1, (quantity) => updateLoad(index, "quantity", quantity));
    const wattsInput = createNumberInput(`${load.name} running watts per item`, load.watts, 1, 100000, 1, (watts) => updateLoad(index, "watts", watts));
    const surgeInput = createNumberInput(`${load.name} startup multiplier`, load.surge, 1, 10, 0.1, (surge) => updateLoad(index, "surge", surge));
    const rowActions = document.createElement("div");
    rowActions.className = "row-actions";
    const moveUpButton = createRowAction("↑", `Move ${load.name} up`, index === 0, () => moveLoad(index, -1));
    const moveDownButton = createRowAction("↓", `Move ${load.name} down`, index === loads.length - 1, () => moveLoad(index, 1));
    const removeButton = createRowAction("×", `Remove ${load.name}`, false, () => {
      loads.splice(index, 1);
      saveLoads();
      render();
    });
    rowActions.append(moveUpButton, moveDownButton, removeButton);

    row.append(name, quantityInput, wattsInput, surgeInput, rowActions);
    loadList.append(row);
  });
}

function updateLoad(index, field, value) {
  loads[index][field] = value;
  saveLoads();
  renderRecommendation();
}

function moveLoad(index, direction) {
  const targetIndex = index + direction;
  if (targetIndex < 0 || targetIndex >= loads.length) return;
  [loads[index], loads[targetIndex]] = [loads[targetIndex], loads[index]];
  saveLoads();
  render();
}

function calculateLoad(items, mode) {
  const running = items.reduce((sum, item) => sum + Number(item.quantity) * Number(item.watts), 0);
  const surges = items.map((item) => Number(item.quantity) * Number(item.watts) * (Number(item.surge) - 1));
  const startupAllowance = mode === "together" ? surges.reduce((sum, surge) => sum + surge, 0) : Math.max(0, ...surges);
  const peak = running + startupAllowance;
  const recommended = peak > 0 ? Math.ceil((peak * 1.2) / 500) * 500 : 0;
  const generator = recommended === 0 ? 0 : generatorSizes.find((size) => size >= recommended) || Math.ceil(recommended / 1000) * 1000;
  return { running, startupAllowance, peak, recommended, generator };
}

function renderRecommendation() {
  const result = calculateLoad(loads, startupMode);
  const shoppingPanel = document.querySelector("#shopping-panel");
  document.querySelector("#recommended-watts").textContent = formatWatts(result.generator);
  document.querySelector("#running-total").textContent = `${formatWatts(result.running)} W`;
  document.querySelector("#surge-total").textContent = `${formatWatts(result.startupAllowance)} W`;
  document.querySelector("#meter-percent").textContent = result.generator ? `${Math.min(100, Math.round((result.running / result.generator) * 100))}%` : "0%";
  document.querySelector("#meter-fill").style.width = `${result.generator ? Math.min(100, (result.running / result.generator) * 100) : 0}%`;
  document.querySelector("#result-title").textContent = result.generator ? `Shop for at least ${formatWatts(result.generator)} rated watts` : "Add loads to size your generator";
  document.querySelector("#recommendation-note").textContent = result.peak ? `${formatWatts(result.peak)} W peak load plus 20% headroom. Startup estimate assumes ${startupMode === "staggered" ? "you start motors one at a time" : "all listed loads start together"}.` : "A 20% headroom is included for a little breathing room.";
  shoppingPanel.hidden = !result.generator;
  if (result.generator) {
    document.querySelector("#shopping-watts").textContent = formatWatts(result.generator);
    document.querySelector("#amazon-search").href = marketplaceSearchUrl("https://www.amazon.co.uk/s", "k", result.generator);
    document.querySelector("#ebay-search").href = marketplaceSearchUrl("https://www.ebay.co.uk/sch/i.html", "_nkw", result.generator);
  }
}

function render() {
  renderLoads();
  renderRecommendation();
}

function addLoad(load) {
  const existing = loads.find((item) => item.name === load.name && item.watts === load.watts && item.surge === load.surge);
  if (existing) existing.quantity += 1;
  else loads.push({ ...load, quantity: 1 });
  saveLoads();
  render();
}

document.querySelector("#add-button").addEventListener("click", () => {
  const preset = presets[Number(presetSelect.value)];
  if (!preset) {
    presetSelect.focus();
    return;
  }
  addLoad(preset);
  presetSelect.value = "";
});

document.querySelector("#custom-button").addEventListener("click", () => customDialog.showModal());
document.querySelector("#save-custom").addEventListener("click", () => {
  if (!customForm.reportValidity()) return;
  const formData = new FormData(customForm);
  addLoad({
    name: String(formData.get("name")).trim(),
    category: "Custom load",
    watts: Number(formData.get("watts")),
    surge: Number(formData.get("surge")),
  });
  customForm.reset();
  customDialog.close();
});

document.querySelectorAll("[data-start-mode]").forEach((button) => {
  button.addEventListener("click", () => {
    startupMode = button.dataset.startMode;
    document.querySelectorAll("[data-start-mode]").forEach((option) => option.setAttribute("aria-pressed", String(option === button)));
    renderRecommendation();
  });
});

document.querySelector("#reload-button").addEventListener("click", () => {
  const savedLoads = loadSavedLoads(previousStorageKey);
  if (!savedLoads.length) return;
  loads = savedLoads;
  saveLoads();
  render();
});

document.querySelector("#reset-button").addEventListener("click", () => {
  if (!loads.length || window.confirm("Remove all appliances from this load list?")) {
    loads = [];
    saveLoads();
    render();
  }
});

render();

if (typeof module !== "undefined") module.exports = { calculateLoad, marketplaceSearchUrl };