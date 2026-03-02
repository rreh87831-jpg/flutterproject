const API_BASE_URL = 'http://localhost:5000/api';
let currentUser = null;
let authToken = localStorage.getItem('authToken');

document.addEventListener('DOMContentLoaded', async () => {
  if (!authToken) {
    showNotification('info', 'No token found. Use localStorage.authToken after login.');
  }
  updateCurrentDate();
  await loadUserData();
  await loadPage('dashboard');
  setupEventListeners();
  startNotificationPolling();
});

function updateCurrentDate() {
  document.getElementById('currentDate').textContent = new Date().toLocaleDateString('en-IN', {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
  });
}

async function loadUserData() {
  try {
    if (!authToken) {
      currentUser = { id: null, full_name: 'Guest', role: 'caregiver' };
      document.getElementById('userName').textContent = currentUser.full_name;
      return;
    }
    const response = await fetch(`${API_BASE_URL}/auth/me`, { headers: { Authorization: `Bearer ${authToken}` } });
    if (!response.ok) throw new Error('Failed to load user data');
    currentUser = await response.json();
    document.getElementById('userName').textContent = currentUser.full_name;
  } catch (error) {
    currentUser = { id: null, full_name: 'Guest', role: 'caregiver' };
    document.getElementById('userName').textContent = currentUser.full_name;
    console.error(error);
  }
}

function setupEventListeners() {
  document.querySelectorAll('.nav-item').forEach((item) => {
    item.addEventListener('click', (e) => {
      document.querySelectorAll('.nav-item').forEach((n) => n.classList.remove('active'));
      e.currentTarget.classList.add('active');
      const page = e.currentTarget.dataset.page;
      document.getElementById('pageTitle').textContent = e.currentTarget.querySelector('span').textContent;
      loadPage(page);
    });
  });

  document.getElementById('logoutBtn').addEventListener('click', logout);
  document.querySelector('.notification-bell').addEventListener('click', showNotifications);
}

async function apiGet(url) {
  const response = await fetch(url, { headers: { Authorization: `Bearer ${authToken}` } });
  if (!response.ok) throw new Error(`Request failed: ${response.status}`);
  return response.json();
}

async function loadPage(page) {
  const body = document.getElementById('contentBody');
  body.innerHTML = '<div class="spinner"></div>';
  try {
    if (page === 'dashboard') return await loadDashboard();
    if (page === 'daily') return await loadDailyActivities();
    if (page === 'weekly') return await loadWeeklyActivities();
    if (page === 'anganwadi') return await loadAnganwadiSchedule();
    if (page === 'reports') return await loadReports();
    if (page === 'children') return await loadChildrenList();
    body.innerHTML = '<p>Page not found</p>';
  } catch (error) {
    console.error(error);
    body.innerHTML = `<p>Failed to load ${page}. ${error.message}</p>`;
  }
}

async function loadDashboard() {
  const body = document.getElementById('contentBody');
  if (!currentUser?.id) {
    body.innerHTML = '<p>Please login to view dashboard.</p>';
    return;
  }
  const endpoint = currentUser.role === 'caregiver'
    ? `${API_BASE_URL}/dashboard/caregiver/${currentUser.id}`
    : `${API_BASE_URL}/dashboard/worker/${currentUser.id}`;
  const data = await apiGet(endpoint);
  body.innerHTML = currentUser.role === 'caregiver' ? renderCaregiverDashboard(data) : renderWorkerDashboard(data);
}

function renderCaregiverDashboard(data) {
  return `<div class="dashboard-stats">
      <div class="stat-card"><div class="stat-icon daily"><i class="fas fa-calendar-day"></i></div><div><div>Today's Progress</div><div class="stat-number">${data.today_summary.completed}/${data.today_summary.total_activities}</div><div>${data.today_summary.pending} pending</div></div></div>
      <div class="stat-card"><div class="stat-icon weekly"><i class="fas fa-calendar-week"></i></div><div><div>Weekly Average</div><div class="stat-number">85%</div><div>Last 7 days</div></div></div>
      <div class="stat-card"><div class="stat-icon anganwadi"><i class="fas fa-child"></i></div><div><div>Children</div><div class="stat-number">${data.children.length}</div><div>Under your care</div></div></div>
      <div class="stat-card"><div class="stat-icon overall"><i class="fas fa-trophy"></i></div><div><div>Overall Progress</div><div class="stat-number">78%</div><div>This month</div></div></div>
    </div>
    <div class="activity-table"><div class="table-header"><h2>Today's Activities</h2><div class="table-actions"><button class="btn btn-outline" onclick="refreshDaily()">Refresh</button></div></div>
    <table><thead><tr><th>Child</th><th>Daily Total</th><th>Done</th></tr></thead><tbody>
    ${data.children.map(c => `<tr><td>${c.full_name}</td><td>${c.today?.total ?? 0}</td><td>${c.today?.completed ?? 0}</td></tr>`).join('')}
    </tbody></table></div>`;
}

function renderWorkerDashboard(data) {
  return `<div class="dashboard-stats">
  <div class="stat-card"><div class="stat-icon daily"><i class="fas fa-calendar-day"></i></div><div><div>Today's Activities</div><div class="stat-number">${data.today_activities.filter(a => a.conducted).length}/${data.today_activities.length}</div></div></div>
  <div class="stat-card"><div class="stat-icon weekly"><i class="fas fa-home"></i></div><div><div>Home Visits</div><div class="stat-number">${data.pending_home_visits.length}</div></div></div>
  <div class="stat-card"><div class="stat-icon anganwadi"><i class="fas fa-users"></i></div><div><div>Children</div><div class="stat-number">${data.children_summary.active}</div></div></div>
  <div class="stat-card"><div class="stat-icon overall"><i class="fas fa-exclamation-triangle"></i></div><div><div>Critical Cases</div><div class="stat-number">${data.children_summary.critical}</div></div></div>
  </div>`;
}

async function loadDailyActivities() {
  const body = document.getElementById('contentBody');
  body.innerHTML = '<p>Select a child from dashboard to view day-wise activities.</p>';
}

async function loadWeeklyActivities() {
  const body = document.getElementById('contentBody');
  body.innerHTML = '<p>Select a child from dashboard to view weekly activities.</p>';
}

async function loadAnganwadiSchedule() {
  const body = document.getElementById('contentBody');
  if (!currentUser?.aanganwadi_center_id) {
    body.innerHTML = '<p>No center assigned.</p>';
    return;
  }
  const today = new Date().toISOString().split('T')[0];
  const schedule = await apiGet(`${API_BASE_URL}/anganwadi/center/${currentUser.aanganwadi_center_id}/week/${today}`);
  body.innerHTML = `<div class="anganwadi-schedule">${schedule.map(day => `<div class="day-card"><div class="day-header ${isToday(day.date) ? 'today' : ''}">${day.day} - ${formatDate(day.date)}</div><div class="day-body">${day.activities.map(a => `<div class="activity-item"><div><strong>${a.activity_name}</strong><p>${a.telugu_description || a.description || ''}</p></div><div>${a.conducted ? 'Done' : 'Pending'}</div></div>`).join('')}</div></div>`).join('')}</div>`;
}

async function loadReports() {
  const body = document.getElementById('contentBody');
  try {
    const daily = await apiGet(`${API_BASE_URL}/reports/daily-progress`);
    body.innerHTML = `<div class="activity-table"><div class="table-header"><h2>Daily Progress Report</h2></div><table><thead><tr><th>Child</th><th>Date</th><th>Completed</th><th>Total</th><th>%</th></tr></thead><tbody>${daily.slice(0,50).map(r => `<tr><td>${r.child_name}</td><td>${formatDate(r.activity_date)}</td><td>${r.completed_count}</td><td>${r.total_count}</td><td>${r.completion_percentage}</td></tr>`).join('')}</tbody></table></div>`;
  } catch (e) {
    body.innerHTML = `<p>${e.message}</p>`;
  }
}

async function loadChildrenList() {
  const body = document.getElementById('contentBody');
  const children = await apiGet(`${API_BASE_URL}/children`);
  body.innerHTML = `<div class="children-grid">${children.map(c => `<div class="child-card"><h3>${c.full_name}</h3><p>${c.child_code}</p><p>DOB: ${formatDate(c.date_of_birth)}</p></div>`).join('')}</div>`;
}

async function markActivityComplete(activityId) {
  try {
    const response = await fetch(`${API_BASE_URL}/daily/${activityId}/complete`, {
      method: 'PUT', headers: { Authorization: `Bearer ${authToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({})
    });
    if (!response.ok) throw new Error('Failed to mark activity complete');
    showNotification('success', 'Activity marked as complete!');
  } catch (error) {
    showNotification('error', error.message);
  }
}

async function completeWeeklyComponent(weeklyId, component) {
  try {
    const response = await fetch(`${API_BASE_URL}/weekly/${weeklyId}/${component}`, {
      method: 'PUT', headers: { Authorization: `Bearer ${authToken}`, 'Content-Type': 'application/json' }
    });
    if (!response.ok) throw new Error('Failed to update weekly activity');
    showNotification('success', 'Weekly activity updated!');
  } catch (error) {
    showNotification('error', error.message);
  }
}

async function conductAnganwadiActivity(activityId) {
  try {
    const response = await fetch(`${API_BASE_URL}/anganwadi/activity/${activityId}/conduct`, {
      method: 'PUT',
      headers: { Authorization: `Bearer ${authToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ start_time: new Date().toTimeString().split(' ')[0], children_present: 0 })
    });
    if (!response.ok) throw new Error('Failed to conduct activity');
    showNotification('success', 'Activity conducted successfully!');
  } catch (error) {
    showNotification('error', error.message);
  }
}

function startNotificationPolling() {
  setInterval(async () => {
    if (!authToken || !currentUser?.id) return;
    try {
      const data = await apiGet(`${API_BASE_URL}/dashboard/caregiver/${currentUser.id}`);
      document.getElementById('notificationCount').textContent = data.notifications?.length || 0;
    } catch (_) {}
  }, 30000);
}

function showNotification(type, message) {
  const n = document.createElement('div');
  n.className = `notification ${type}`;
  n.innerHTML = `<span>${message}</span>`;
  document.body.appendChild(n);
  setTimeout(() => n.remove(), 3000);
}

function showNotifications() { showNotification('info', 'Notification panel can be added here.'); }
function showAddChildModal() { showNotification('info', 'Add-child modal can be added here.'); }
function showHomeVisitModal() { showNotification('info', 'Home visit modal can be added here.'); }
function showReviewModal() { showNotification('info', 'Review modal can be added here.'); }
function showDayDetails() { showNotification('info', 'Day detail modal can be added here.'); }
function showDailyCalendar() { showNotification('info', 'Calendar view can be added here.'); }

function isToday(dateStr) { return dateStr === new Date().toISOString().split('T')[0]; }
function formatDate(date) {
  if (!date) return '-';
  const d = new Date(date);
  if (Number.isNaN(d.getTime())) return String(date);
  return d.toLocaleDateString('en-GB');
}

function logout() {
  localStorage.removeItem('authToken');
  location.reload();
}

window.markActivityComplete = markActivityComplete;
window.completeWeeklyComponent = completeWeeklyComponent;
window.conductAnganwadiActivity = conductAnganwadiActivity;
window.loadPage = loadPage;
window.refreshDaily = () => loadPage('daily');
window.markAllComplete = () => showNotification('info', 'Bulk complete feature coming soon');
