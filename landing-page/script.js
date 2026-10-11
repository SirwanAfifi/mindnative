const views = {
  project: { src: "assets/project-map.webp", name: "Project map", detail: " — Connect ideas. Add detail.", alt: "MindNative with a New Project map connected to Goals, Milestones, Tasks, Risks, and Resources" },
  blank: { src: "assets/blank-canvas.webp", name: "Blank canvas", detail: " — Add your first idea.", alt: "MindNative blank canvas with New idea, Brainstorm, and Template controls" },
};
const viewControls = document.querySelector(".view-controls");
const viewImage = document.querySelector("#app-view");
const viewFrame = document.querySelector("#app-frame");
const viewStatus = document.querySelector("#view-status");
const viewButtons = [...viewControls.querySelectorAll("button")];
let requestedView = "project";
viewControls.hidden = false;
for (const button of viewButtons) {
  button.addEventListener("click", async () => {
    const key = button.dataset.view;
    if (button.getAttribute("aria-pressed") === "true" && requestedView === key) return;
    requestedView = key;
    const view = views[key];
    const preload = new Image();
    preload.src = view.src;
    viewStatus.textContent = `Loading ${view.name.toLowerCase()}.`;
    viewFrame.setAttribute("aria-busy", "true");
    try {
      await preload.decode();
      if (requestedView !== key) return;
      viewImage.src = view.src;
      viewImage.alt = view.alt;
      document.querySelector("#view-name").textContent = view.name;
      document.querySelector("#view-detail").textContent = view.detail;
      for (const item of viewButtons) item.setAttribute("aria-pressed", String(item === button));
      viewFrame.classList.remove("is-changing");
      void viewFrame.offsetWidth;
      viewFrame.classList.add("is-changing");
      viewStatus.textContent = `${view.name} shown.`;
    } catch {
      if (requestedView === key) viewStatus.textContent = "The app view could not load. Select a view to try again.";
    } finally {
      if (requestedView === key) viewFrame.removeAttribute("aria-busy");
    }
  });
}
const copyButton = document.querySelector("#copy-command");
const copyStatus = document.querySelector("#copy-status");
if (navigator.clipboard && window.isSecureContext) {
  copyButton.hidden = false;
  copyButton.addEventListener("click", async () => {
    copyButton.disabled = true;
    try {
      await navigator.clipboard.writeText(document.querySelector("#build-command").textContent);
      copyStatus.textContent = "Commands copied. Paste them in Terminal.";
    } catch {
      copyStatus.textContent = "Copy did not work. Select the commands and copy them manually.";
    } finally {
      copyButton.disabled = false;
    }
  });
}
