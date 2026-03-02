const API_BASE_URL = 'http://localhost:5000/api';
const REFERRAL_NUMBER = 'REF-20260302-0020';

document.addEventListener('DOMContentLoaded', async () => {
  updateCurrentDate();
  setupNav();
  await loadReferralData();
  await loadPage('referral');
});

function updateCurrentDate() {
  const today = new Date().toLocaleDateString('en-IN', {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
  });
  document.getElementById('currentDate').textContent = today;
}

function setupNav() {
  document.querySelectorAll('.nav-item').forEach((item) => {
    item.addEventListener('click', async (e) => {
      document.querySelectorAll('.nav-item').forEach((i) => i.classList.remove('active'));
      e.currentTarget.classList.add('active');
      const page = e.currentTarget.dataset.page;
      const title = {
        referral: 'Referral Overview',
        caregiver: 'Caregiver Activities',
        aww: 'AWW Monitoring Activities',
        followup: 'Follow-Up Plan',
      };
      document.getElementById('pageTitle').textContent = title[page];
      await loadPage(page);
    });
  });
}

async function loadReferralData() {
  try {
    const res = await fetch(`${API_BASE_URL}/referrals/${REFERRAL_NUMBER}`);
    if (!res.ok) return;
    const data = await res.json();
    document.getElementById('progressPercent').textContent = `${data.progress_percentage}%`;
    document.getElementById('progressFill').style.width = `${data.progress_percentage}%`;
    document.getElementById('completedCount').textContent = data.completed_activities;
    document.getElementById('totalCount').textContent = data.total_activities;
  } catch (_) {}
}

async function loadPage(page) {
  const body = document.getElementById('contentBody');
  body.innerHTML = '<div class="loading-spinner"></div>';
  if (page === 'referral') return loadReferralPage();
  if (page === 'caregiver') return loadCaregiverPage();
  if (page === 'aww') return loadAwwPage();
  if (page === 'followup') return loadFollowupPage();
}

async function loadReferralPage() {
  const [r, t] = await Promise.all([
    fetch(`${API_BASE_URL}/referrals/${REFERRAL_NUMBER}`).then((x) => x.json()),
    fetch(`${API_BASE_URL}/followup/${REFERRAL_NUMBER}/timeline`).then((x) => x.json()),
  ]);

  document.getElementById('contentBody').innerHTML = `
    <div class="card">
      <h3>${r.referral_number}</h3>
      <p>${r.facility}</p>
      <p><b>Deadline:</b> ${r.referral_deadline} (${r.days_remaining} days)</p>
      <div class="timeline-grid" style="margin-top:10px;">
        ${t.map((i) => `<div class="card"><div>${i.event}</div><div><b>${i.date}</b></div><div>${i.details}</div></div>`).join('')}
      </div>
    </div>
  `;
}

async function loadCaregiverPage() {
  const data = await fetch(`${API_BASE_URL}/caregiver/${REFERRAL_NUMBER}/activities`).then((x) => x.json());
  const block = (name, rows) => `
    <h3 style="margin:12px 0;">${name} Activities</h3>
    <div class="activity-grid">${rows.map((a) => `
      <div class="activity-card">
        <div class="activity-type"><span class="type-badge">${name}</span><span class="level-badge">Level ${a.level_number}</span></div>
        <div>${a.telugu_description || ''}</div>
        <div class="activity-footer">
          <span class="activity-meta">CAREGIVER</span>
          ${a.completed ? '<span class="completed-badge">100% complete</span>' : `<button class="btn btn-primary" onclick="markCaregiverComplete('${a.id}')">Mark as Completed</button>`}
        </div>
      </div>
    `).join('')}</div>
  `;
  document.getElementById('contentBody').innerHTML = `<div class="activity-section"><h2>Caregiver Activities</h2>${block('GM', data.GM || [])}${block('LC', data.LC || [])}${block('COG', data.COG || [])}</div>`;
}

async function loadAwwPage() {
  const rows = await fetch(`${API_BASE_URL}/aww/${REFERRAL_NUMBER}/activities`).then((x) => x.json());
  document.getElementById('contentBody').innerHTML = `
    <div class="activity-section">
      <h2>AWW Monitoring Activities</h2>
      <div style="margin-bottom:12px;">
        <label><input type="checkbox" id="escalationCheck" /> Escalation Required</label>
        <label style="margin-left:12px;"><input type="checkbox" id="okCheck" /> OK</label>
      </div>
      <div class="activity-grid">
        ${rows.map((a) => `
          <div class="activity-card">
            <div class="activity-type"><span class="type-badge">${a.activity_type}</span><span class="level-badge">Level ${a.level_number}</span></div>
            <div>${a.telugu_description || ''}</div>
            <div class="activity-footer">
              <span class="activity-meta">AWW</span>
              ${a.marked_monitored ? '<span class="completed-badge">Monitored</span>' : `<button class="btn btn-outline" onclick="markAwwMonitored('${a.id}')">Mark as Monitored</button>`}
            </div>
          </div>
        `).join('')}
      </div>
    </div>
  `;
}

async function loadFollowupPage() {
  const plan = await fetch(`${API_BASE_URL}/followup/${REFERRAL_NUMBER}/plan`).then((x) => x.json());
  const render = (title, rows) => `
    <h3 style="margin:10px 0;">${title}</h3>
    ${rows.length ? rows.map((i) => `<div class="followup-item"><div style="min-width:100px;">${i.followup_date}</div><div style="min-width:80px;">Level ${i.level_number}</div><div style="flex:1;">${i.status}</div>${!i.completed ? `<button class="btn btn-primary" onclick="markFollowupComplete('${i.id}')">Mark Complete</button>` : '<span class="completed-badge">Completed</span>'}</div>`).join('') : '<p>No items</p>'}
  `;
  document.getElementById('contentBody').innerHTML = `
    <div class="activity-section">
      <h2>Follow-Up Plan</h2>
      ${render('Today', plan.today || [])}
      ${render('Upcoming', plan.upcoming || [])}
      ${render('Completed', plan.completed || [])}
    </div>
  `;
}

async function markCaregiverComplete(activityId) {
  const res = await fetch(`${API_BASE_URL}/caregiver/activity/${activityId}/complete`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) });
  if (res.ok) {
    await loadReferralData();
    await loadPage('caregiver');
  }
}

async function markAwwMonitored(activityId) {
  const escalation = document.getElementById('escalationCheck')?.checked || false;
  const ok = document.getElementById('okCheck')?.checked || false;
  const res = await fetch(`${API_BASE_URL}/aww/activity/${activityId}/monitor`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ escalation_required: escalation, ok_status: ok }),
  });
  if (res.ok) {
    await loadReferralData();
    await loadPage('aww');
  }
}

async function markFollowupComplete(followupId) {
  const res = await fetch(`${API_BASE_URL}/followup/${followupId}/complete`, { method: 'PUT' });
  if (res.ok) await loadPage('followup');
}

window.markCaregiverComplete = markCaregiverComplete;
window.markAwwMonitored = markAwwMonitored;
window.markFollowupComplete = markFollowupComplete;
