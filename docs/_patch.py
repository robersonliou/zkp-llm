import re, sys

f = open('docs/index.html', encoding='utf-8')
c = f.read()
f.close()

# ─── 1. CSS ──────────────────────────────────────────────────────────
CSS = """
    /* --- Cover slide ----------------------------------------------- */
    .cover-slide {
      background: radial-gradient(ellipse at 30% 50%, #0d1f35 0%, #0e1117 70%);
      align-items: center;
      justify-content: center;
    }
    .cover-body { display:flex; flex-direction:column; align-items:center; width:100%; }
    .nccu-brand { display:flex; flex-direction:column; align-items:center; margin-bottom:18px; }
    .nccu-seal  { width:76px; height:76px; margin-bottom:8px; }
    .nccu-name-zh { font-size:1.25rem; font-weight:700; color:var(--text); letter-spacing:0.18em; }
    .nccu-name-en { font-size:0.74rem; color:var(--muted); letter-spacing:0.1em; margin-top:2px; }
    .cover-hr   { width:320px; height:1px; background:var(--border); margin:14px 0; }
    .cover-course { font-size:0.82rem; color:var(--accent4); letter-spacing:0.08em; margin-bottom:8px; text-align:center; }
    .cover-h1   { font-size:2.8rem; font-weight:800; margin-bottom:6px;
                  background:linear-gradient(90deg,var(--accent),var(--accent4));
                  -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
    .cover-sub  { font-size:0.98rem; color:var(--muted); margin-bottom:22px; }
    .cover-members { display:flex; align-items:center; gap:18px; margin-bottom:10px; }
    .cv-member  { font-size:1.05rem; font-weight:600; color:var(--text); }
    .cv-sep     { color:var(--border); font-size:1.3rem; }
    .cover-date { font-size:0.78rem; color:var(--muted); }
    /* --- Section divider slides ------------------------------------ */
    .divider-slide {
      background: linear-gradient(135deg,#0d1f35 0%,#0e1117 55%,#150d20 100%);
      align-items: flex-start;
      justify-content: center;
      padding-left: 110px;
    }
    .dv-part  { font-size:0.8rem; font-weight:700; letter-spacing:0.22em;
                text-transform:uppercase; color:var(--accent); margin-bottom:10px; }
    .dv-title { font-size:2.5rem; font-weight:800; color:var(--text); line-height:1.1; margin-bottom:6px; }
    .dv-b .dv-title { color:var(--accent4); }
    .dv-c .dv-title { color:var(--accent2); }
    .dv-presenter { font-size:0.88rem; color:var(--muted); margin-bottom:24px; }
    .dv-outline   { list-style:none; padding:0; border-left:3px solid var(--border); padding-left:18px; }
    .dv-outline li{ font-size:0.86rem; color:var(--muted); line-height:1.9; }
    .dv-range { margin-top:20px; font-size:0.74rem; color:var(--border); letter-spacing:0.05em; }
"""
c = c.replace('  </style>\n</head>', CSS + '  </style>\n</head>')
assert 'cover-slide' in c, 'CSS insert failed'
print('1. CSS ok')

# ─── 2. Cover + Divider A + remove active from original title slide ──
COVER_AND_DIVIDER_A = """      <!-- COVER ================================================== -->
      <section class="slide cover-slide active">
        <span class="slide-num"></span>
        <div class="cover-body">
          <div class="nccu-brand">
            <svg class="nccu-seal" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
              <circle cx="50" cy="50" r="46" stroke="#58a6ff" stroke-width="2"/>
              <circle cx="50" cy="50" r="38" stroke="#58a6ff" stroke-width="0.6" stroke-dasharray="4 3"/>
              <text x="50" y="48" text-anchor="middle" dominant-baseline="middle"
                    font-size="20" font-weight="bold" fill="#58a6ff" font-family="serif">\u653f\u5927</text>
              <text x="50" y="66" text-anchor="middle" font-size="7" fill="#8b949e" letter-spacing="1">NCCU</text>
              <text x="50" y="33" text-anchor="middle" font-size="6" fill="#8b949e" letter-spacing="1">EST. 1927</text>
            </svg>
            <div class="nccu-name-zh">\u570b\u7acb\u653f\u6cbb\u5927\u5b78</div>
            <div class="nccu-name-en">National Chengchi University</div>
          </div>
          <div class="cover-hr"></div>
          <div class="cover-course">\u5bc6\u78bc\u5b78 &nbsp;&middot;&nbsp; NCCU 11502 &nbsp;&middot;&nbsp; \u671f\u672b\u5c08\u984c</div>
          <div class="cover-h1">ZKP in LLM</div>
          <div class="cover-sub">Verifiable AI Agent on Cartesi</div>
          <div class="cover-members">
            <span class="cv-member">\u6797\u7a4e\u5f65</span>
            <span class="cv-sep">&middot;</span>
            <span class="cv-member">\u5289\u66f8\u50b3</span>
            <span class="cv-sep">&middot;</span>
            <span class="cv-member">\u738b\u96c5\u9e97</span>
          </div>
          <div class="cover-date">2026-06-08</div>
        </div>
      </section>

      <!-- DIVIDER A \u2014 Part I ====================================== -->
      <section class="slide divider-slide">
        <span class="slide-num"></span>
        <div class="dv-part">Part I</div>
        <div class="dv-title">ZKP Theory Foundation</div>
        <div class="dv-presenter">Presenter &nbsp;&middot;&nbsp; \u6797\u7a4e\u5f65</div>
        <ul class="dv-outline">
          <li>Why Verify LLM Agents? &amp; Motivating Scenario</li>
          <li>ZKP Primer \u2014 Interactive \u2192 Non-interactive (Fiat-Shamir)</li>
          <li>ZKP Family Tree &amp; Coursework Connections</li>
          <li>SNARK vs STARK &amp; Lookup Arguments</li>
        </ul>
        <div class="dv-range">Slides 3 \u2013 10</div>
      </section>

      <!-- SLIDE 1 \u2014 Title ========================================= -->
      <section class="slide title-slide">
"""

# Find and replace the original title slide opening
import re
OLD_TITLE = ('      <!-- \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550'
             '\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550'
             '\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550'
             '\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\n'
             '         SLIDE 1 \u2014 Title\n'
             '    \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550'
             '\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550'
             '\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550'
             '\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550 -->\n'
             '      <section class="slide title-slide active">')

# Simpler: just search for the specific pattern
idx = c.find('<section class="slide title-slide active">')
assert idx != -1, 'title-slide active not found'

# Find the start of the comment block before it
comment_start = c.rfind('      <!-- ', 0, idx)
replacement = COVER_AND_DIVIDER_A
c = c[:comment_start] + replacement + c[idx + len('<section class="slide title-slide active">'):]
assert 'cover-body' in c, 'cover insert failed'
print('2. Cover + DividerA ok')

# ─── 3. Insert Divider B before Slide 9 ──────────────────────────────
DIVIDER_B = """      <!-- DIVIDER B \u2014 Part II ===================================== -->
      <section class="slide divider-slide dv-b">
        <span class="slide-num"></span>
        <div class="dv-part">Part II</div>
        <div class="dv-title">Core Papers</div>
        <div class="dv-presenter">Presenter &nbsp;&middot;&nbsp; \u5289\u66f8\u50b3</div>
        <ul class="dv-outline">
          <li>zkVM Landscape &amp; Folding Schemes</li>
          <li>zkLLM \u2014 tlookup &amp; zkAttn 5-Step Flow</li>
          <li>zkRAG \u2014 Verifiable HNSW Search</li>
          <li>EZKL \u2014 ONNX \u2192 Halo2 \u2192 Solidity Verifier</li>
          <li>Benchmark Comparison</li>
        </ul>
        <div class="dv-range">Slides 12 \u2013 19</div>
      </section>

"""
SLIDE9_MARKER = 'SLIDE 9 \u2014 zkVM Landscape'
idx9 = c.find(SLIDE9_MARKER)
assert idx9 != -1, 'slide 9 marker not found'
comment9 = c.rfind('      <!-- ', 0, idx9)
c = c[:comment9] + DIVIDER_B + c[comment9:]
assert 'Part II' in c, 'divider B insert failed'
print('3. Divider B ok')

# ─── 4. Insert Divider C before Slide 17 ─────────────────────────────
DIVIDER_C = """      <!-- DIVIDER C \u2014 Part III ==================================== -->
      <section class="slide divider-slide dv-c">
        <span class="slide-num"></span>
        <div class="dv-part">Part III</div>
        <div class="dv-title">System Integration<br>+ Demo</div>
        <div class="dv-presenter">Presenter &nbsp;&middot;&nbsp; \u738b\u96c5\u9e97</div>
        <ul class="dv-outline">
          <li>DEAAP Pipeline &amp; Cartesi v0.20.0 Highlights</li>
          <li>RISC0 Step Prover &amp; Target Architecture</li>
          <li>Hybrid Rollup Design</li>
          <li>Demo A (EZKL) &amp; Demo B (RISC0 \u00d7 Cartesi)</li>
          <li>Future Directions &amp; Limitations</li>
        </ul>
        <div class="dv-range">Slides 21 \u2013 31</div>
      </section>

"""
SLIDE17_MARKER = 'SLIDE 17 \u2014 DEAAP Pipeline Overview'
idx17 = c.find(SLIDE17_MARKER)
assert idx17 != -1, 'slide 17 marker not found'
comment17 = c.rfind('      <!-- ', 0, idx17)
c = c[:comment17] + DIVIDER_C + c[comment17:]
assert 'Part III' in c, 'divider C insert failed'
print('4. Divider C ok')

# ─── 5. Dynamic slide numbers ─────────────────────────────────────────
OLD_SHOW = """    function show(idx) {
      slides[current].classList.remove('active');
      current = (idx + total) % total;
      slides[current].classList.add('active');
      counter.textContent = `${current + 1} / ${total}`;
      progress.style.width = `${((current + 1) / total) * 100}%`;
    }"""
NEW_SHOW = """    function show(idx) {
      slides[current].classList.remove('active');
      current = (idx + total) % total;
      slides[current].classList.add('active');
      counter.textContent = `${current + 1} / ${total}`;
      progress.style.width = `${((current + 1) / total) * 100}%`;
      var numEl = slides[current].querySelector('.slide-num');
      if (numEl) numEl.textContent = (current + 1) + ' / ' + total;
    }

    function initSlideNums() {
      slides.forEach(function(s, i) {
        var el = s.querySelector('.slide-num');
        if (el) el.textContent = (i + 1) + ' / ' + total;
      });
    }
    initSlideNums();"""
assert OLD_SHOW in c, 'show() not found'
c = c.replace(OLD_SHOW, NEW_SHOW)
print('5. Dynamic slide nums ok')

# ─── 6. Write ─────────────────────────────────────────────────────────
with open('docs/index.html', 'w', encoding='utf-8') as f:
    f.write(c)
print('Done. Lines:', c.count('\n'), '| Slides ~31')
