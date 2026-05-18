(() => {
    const root = document.getElementById('root');
    const viewLeaderboard = document.getElementById('view-leaderboard');
    const viewEditor = document.getElementById('view-editor');

    let editorState = { points: [], neighbors: {}, gangs: {}, zones: [], linkSrc: null };

    // ============ helpers ============
    const post = (name, data) =>
        fetch(`https://${GetParentResourceName()}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});

    const show = (which) => {
        root.classList.remove('hidden');
        viewLeaderboard.classList.add('hidden');
        viewEditor.classList.add('hidden');
        if (which === 'leaderboard') viewLeaderboard.classList.remove('hidden');
        if (which === 'editor') viewEditor.classList.remove('hidden');
    };
    const hideAll = () => {
        root.classList.add('hidden');
        viewLeaderboard.classList.add('hidden');
        viewEditor.classList.add('hidden');
    };

    // ============ leaderboard ============
    const renderLeaderboard = (board, recent) => {
        const ul = document.getElementById('standings');
        ul.innerHTML = '';
        board.gangs.forEach((g, i) => {
            const li = document.createElement('li');
            li.style.borderLeftColor = g.color_hex;
            li.innerHTML = `
                <span class="rank">#${i + 1}</span>
                <span class="name" style="color:${g.color_hex}">${g.label}</span>
                <span class="pct">${g.percent.toFixed(1)}%</span>
                <span class="pts">${g.points} pts</span>
                <div class="bar"><span style="width:${g.percent}%;background:${g.color_hex}"></span></div>
            `;
            ul.appendChild(li);
        });
        const rec = document.getElementById('recent');
        rec.innerHTML = '';
        recent.forEach((r) => {
            const li = document.createElement('li');
            const dot = `<span class="swatch" style="background:${r.to_color || '#888'}"></span>`;
            li.innerHTML = `<span>${dot}#${r.point_id} → ${r.to_label || r.to_job}</span>
                            <span>${new Date(r.captured_at).toLocaleTimeString()}</span>`;
            rec.appendChild(li);
        });
    };

    // ============ editor ============
    const gangOptionsHTML = (selectedJob) => {
        const opts = ['<option value="">— set HQ —</option>'];
        Object.entries(editorState.gangs).forEach(([job, g]) => {
            const sel = selectedJob === job ? 'selected' : '';
            opts.push(`<option value="${job}" ${sel}>${g.label}</option>`);
        });
        return opts.join('');
    };

    const zoneOptionsHTML = (selectedId) => {
        const opts = ['<option value="">— no zone —</option>'];
        editorState.zones.forEach((z) => {
            const sel = Number(selectedId) === z.id ? 'selected' : '';
            opts.push(`<option value="${z.id}" ${sel}>${z.name} (#${z.id})</option>`);
        });
        return opts.join('');
    };

    const renderEditor = () => {
        // ---- Zones panel ----
        const zonesList = document.getElementById('zones');
        zonesList.innerHTML = '';
        editorState.zones.forEach((z) => {
            const li = document.createElement('li');
            li.className = 'zone-row';
            const sized = z.min_x !== z.max_x && z.min_y !== z.max_y;
            const dims = sized
                ? `${Math.abs(z.max_x - z.min_x).toFixed(0)} × ${Math.abs(z.max_y - z.min_y).toFixed(0)}`
                : '<em>not sized</em>';
            li.innerHTML = `
                <div class="zone-head">
                    <strong>#${z.id} ${z.name}</strong>
                    <span class="zone-dims">${dims}</span>
                </div>
                <div class="zone-actions">
                    <button data-zact="cornerA" data-id="${z.id}">Set A</button>
                    <button data-zact="cornerB" data-id="${z.id}">Set B</button>
                    <button data-zact="auto"    data-id="${z.id}">Auto-assign</button>
                    <button data-zact="rename"  data-id="${z.id}">Rename</button>
                    <button data-zact="delete"  data-id="${z.id}" class="danger">del</button>
                </div>`;
            zonesList.appendChild(li);
        });

        // ---- Gangs panel ----
        const gangsList = document.getElementById('gangs');
        gangsList.innerHTML = '';
        Object.entries(editorState.gangs).forEach(([job, g]) => {
            const li = document.createElement('li');
            li.style.borderLeftColor = g.color_hex;
            const hq = g.hq_point_id ? ` · HQ #${g.hq_point_id}` : '';
            li.innerHTML = `<span style="color:${g.color_hex}">${g.label}${hq}</span>
                            <span>${job}</span>`;
            gangsList.appendChild(li);
        });

        // ---- Points table ----
        const body = document.getElementById('points-body');
        const filter = (document.getElementById('filter').value || '').toLowerCase();
        body.innerHTML = '';

        editorState.points
            .filter((p) => {
                if (!filter) return true;
                return String(p.id).includes(filter)
                    || (p.owner_job || 'neutral').toLowerCase().includes(filter);
            })
            .sort((a, b) => a.id - b.id)
            .forEach((p) => {
                const tr = document.createElement('tr');
                const ownerJob = p.owner_job || '—';
                const ownerColor = (editorState.gangs[p.owner_job] || {}).color_hex || '#555';
                const neighbors = (editorState.neighbors[p.id] || []).join(', ') || '—';
                tr.innerHTML = `
                    <td>#${p.id}</td>
                    <td>${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}</td>
                    <td>
                        <span class="swatch" style="background:${ownerColor}"></span>${ownerJob}
                        <select class="hq-select" data-id="${p.id}">${gangOptionsHTML(null)}</select>
                    </td>
                    <td>
                        <select class="zone-select" data-id="${p.id}">${zoneOptionsHTML(p.zone_id)}</select>
                    </td>
                    <td>${neighbors}</td>
                    <td class="row-actions">
                        <button data-act="tp"    data-id="${p.id}">tp</button>
                        <button data-act="link"  data-id="${p.id}">link</button>
                        <button data-act="del"   data-id="${p.id}" class="danger">del</button>
                    </td>`;
                body.appendChild(tr);
            });

        const linkLabel = document.getElementById('link-mode');
        const cancelBtn = document.getElementById('btn-cancel-link');
        if (editorState.linkSrc) {
            linkLabel.classList.remove('hidden');
            linkLabel.textContent = `Linking from #${editorState.linkSrc} → click another row's "link"`;
            cancelBtn.classList.remove('hidden');
        } else {
            linkLabel.classList.add('hidden');
            cancelBtn.classList.add('hidden');
        }
    };

    // ============ NUI message handler ============
    window.addEventListener('message', (e) => {
        const m = e.data;
        if (m.action === 'openLeaderboard') {
            renderLeaderboard(m.board, m.recent || []);
            show('leaderboard');
        } else if (m.action === 'openEditor') {
            show('editor');
        } else if (m.action === 'editorData') {
            editorState = {
                points: m.points || [],
                neighbors: m.neighbors || {},
                gangs: m.gangs || {},
                zones: m.zones || [],
                linkSrc: m.linkSrc || null,
            };
            renderEditor();
        } else if (m.action === 'close') {
            hideAll();
        }
    });

    // ============ key handler (ESC) ============
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            if (!viewLeaderboard.classList.contains('hidden')) post('closeLeaderboard');
            if (!viewEditor.classList.contains('hidden')) post('closeEditor');
        }
    });

    // ============ close buttons ============
    document.querySelectorAll('.close').forEach((btn) =>
        btn.addEventListener('click', () => {
            const w = btn.getAttribute('data-close');
            post(w === 'leaderboard' ? 'closeLeaderboard' : 'closeEditor');
        }),
    );

    // ============ editor controls ============
    document.getElementById('btn-create').addEventListener('click', () => {
        post('createHere', {});
    });
    document.getElementById('btn-cancel-link').addEventListener('click', () => {
        post('cancelLink');
    });
    document.getElementById('filter').addEventListener('input', renderEditor);

    document.getElementById('points-body').addEventListener('click', (e) => {
        const btn = e.target.closest('button[data-act]');
        if (!btn) return;
        const id = btn.getAttribute('data-id');
        const act = btn.getAttribute('data-act');
        if (act === 'tp') post('teleportTo', { id });
        if (act === 'del' && confirm(`Delete point #${id}?`)) post('deletePoint', { id });
        if (act === 'link') {
            if (editorState.linkSrc && Number(editorState.linkSrc) !== Number(id)) {
                post('finishLink', { id });
            } else {
                post('startLink', { id });
            }
        }
    });

    document.getElementById('gang-form').addEventListener('submit', (e) => {
        e.preventDefault();
        const f = new FormData(e.target);
        post('setGang', {
            job:   f.get('job'),
            label: f.get('label'),
            color: f.get('color'),
            blip:  f.get('blip'),
        });
        e.target.reset();
    });

    // ---- Zone form ----
    document.getElementById('zone-form').addEventListener('submit', (e) => {
        e.preventDefault();
        const f = new FormData(e.target);
        post('createZone', { name: f.get('name') });
        e.target.reset();
    });

    document.getElementById('zones').addEventListener('click', (e) => {
        const btn = e.target.closest('button[data-zact]');
        if (!btn) return;
        const id  = btn.getAttribute('data-id');
        const act = btn.getAttribute('data-zact');
        if (act === 'cornerA') post('setZoneCorner', { id, which: 'A' });
        if (act === 'cornerB') post('setZoneCorner', { id, which: 'B' });
        if (act === 'auto')    post('autoAssignZone', { id });
        if (act === 'rename') {
            const name = prompt('New zone name:');
            if (name) post('renameZone', { id, name });
        }
        if (act === 'delete' && confirm(`Delete zone #${id}? Points will be unassigned.`)) {
            post('deleteZone', { id });
        }
    });

    // ---- HQ + zone selects in the points table ----
    document.getElementById('points-body').addEventListener('change', (e) => {
        if (e.target.classList.contains('hq-select')) {
            const id  = e.target.getAttribute('data-id');
            const job = e.target.value;
            if (job) post('setHQ', { id, job });
        } else if (e.target.classList.contains('zone-select')) {
            const pointId = e.target.getAttribute('data-id');
            const zoneId  = e.target.value;
            post('assignPointZone', { pointId, zoneId });
        }
    });
})();
