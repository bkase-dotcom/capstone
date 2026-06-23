/* =============================================================================
 * ui.js — builds the HTML control bars and exposes a shared UI state object.
 * Kept outside the p5 canvas so canvas pointer events are reserved for the
 * fire / tune gesture.
 * ===========================================================================*/

const UI = {
  model: 'bohr',
  lightMode: 'monochromatic',   // 'monochromatic' | 'white'
  beamOn: false,
  paused: false,
  simSpeed: 1,
  handTracking: false,
  // callbacks (assigned by sketch)
  onModelChange: null,
  onReset: null,
  onClear: null,
  onToggleHand: null,
  _modelButtons: {},
  _handBtn: null,
  _beamBtn: null,
  _pauseBtn: null,
};

function buildUI(models) {
  const bar = document.getElementById('toolbar');

  // --- model segmented control (grouped classical / quantum) -------------
  const mkGroup = (title) => {
    const g = document.createElement('div'); g.className = 'group';
    const t = document.createElement('span'); t.className = 'group-label'; t.textContent = title;
    g.appendChild(t); bar.appendChild(g); return g;
  };
  const classical = mkGroup('Classical');
  const quantum = mkGroup('Quantum');
  for (const key in models) {
    const m = models[key];
    const b = document.createElement('button');
    b.className = 'seg'; b.textContent = m.label; b.dataset.key = key;
    b.onclick = () => setModel(key);
    UI._modelButtons[key] = b;
    (m.type === 'classical' ? classical : quantum).appendChild(b);
  }

  function setModel(key) {
    UI.model = key;
    for (const k in UI._modelButtons)
      UI._modelButtons[k].classList.toggle('active', k === key);
    if (UI.onModelChange) UI.onModelChange(key);
  }
  UI.setModel = setModel;

  // --- right-side action buttons -----------------------------------------
  const actions = document.createElement('div'); actions.className = 'group right';
  bar.appendChild(actions);

  const lightBtn = document.createElement('button');
  lightBtn.className = 'btn'; lightBtn.textContent = '◐ Monochromatic';
  lightBtn.onclick = () => {
    UI.lightMode = UI.lightMode === 'white' ? 'monochromatic' : 'white';
    lightBtn.textContent = UI.lightMode === 'white' ? '○ White light' : '◐ Monochromatic';
  };
  actions.appendChild(lightBtn);

  UI._beamBtn = document.createElement('button');
  UI._beamBtn.className = 'btn'; UI._beamBtn.textContent = '▶ Beam: off';
  UI._beamBtn.onclick = () => {
    UI.beamOn = !UI.beamOn;
    UI._beamBtn.textContent = UI.beamOn ? '■ Beam: on' : '▶ Beam: off';
    UI._beamBtn.classList.toggle('on', UI.beamOn);
  };
  actions.appendChild(UI._beamBtn);

  UI._handBtn = document.createElement('button');
  UI._handBtn.className = 'btn'; UI._handBtn.textContent = '✋ Hand tracking: off';
  UI._handBtn.onclick = () => { if (UI.onToggleHand) UI.onToggleHand(); };
  actions.appendChild(UI._handBtn);

  UI._pauseBtn = document.createElement('button');
  UI._pauseBtn.className = 'btn'; UI._pauseBtn.textContent = '⏸ Pause';
  UI._pauseBtn.onclick = () => {
    UI.paused = !UI.paused;
    UI._pauseBtn.textContent = UI.paused ? '▶ Play' : '⏸ Pause';
  };
  actions.appendChild(UI._pauseBtn);

  const resetBtn = document.createElement('button');
  resetBtn.className = 'btn'; resetBtn.textContent = '↺ Reset atom';
  resetBtn.onclick = () => { if (UI.onReset) UI.onReset(); };
  actions.appendChild(resetBtn);

  const clearBtn = document.createElement('button');
  clearBtn.className = 'btn'; clearBtn.textContent = '⌫ Clear spectrum';
  clearBtn.onclick = () => { if (UI.onClear) UI.onClear(); };
  actions.appendChild(clearBtn);

  setModel(UI.model);
}

function setHandButton(state) {
  // state: 'off' | 'loading' | 'on' | 'error'
  if (!UI._handBtn) return;
  const txt = {
    off: '✋ Hand tracking: off',
    loading: '… loading model',
    on: '✋ Hand tracking: ON',
    error: '⚠ camera error',
  };
  UI._handBtn.textContent = txt[state];
  UI._handBtn.classList.toggle('on', state === 'on');
}
