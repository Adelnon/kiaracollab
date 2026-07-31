/* Poll the bot's live status and reflect it in the page.
 *
 * The Flask server exposes /api/status backed by the bot's shared snapshot.
 * If the endpoint isn't reachable (e.g. the page is opened as a static file
 * with no server, or the bot is down), we fail gracefully to an "offline"
 * state rather than throwing.
 */
(function () {
  "use strict";

  var POLL_MS = 10000;

  var pill = document.getElementById("status-pill");
  var statusText = document.getElementById("status-text");
  var liveNote = document.getElementById("live-note");
  var el = {
    status: document.getElementById("stat-status"),
    guilds: document.getElementById("stat-guilds"),
    members: document.getElementById("stat-members"),
    uptime: document.getElementById("stat-uptime"),
  };

  function formatUptime(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0));
    var d = Math.floor(seconds / 86400);
    var h = Math.floor((seconds % 86400) / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    if (d > 0) return d + "d " + h + "h";
    if (h > 0) return h + "h " + m + "m";
    return m + "m";
  }

  function formatCount(n) {
    if (typeof n !== "number") return "—";
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M";
    if (n >= 1000) return (n / 1000).toFixed(1) + "k";
    return String(n);
  }

  function setPill(state, label) {
    pill.className = "status-pill status-" + state;
    statusText.textContent = label;
  }

  function render(data) {
    if (data && data.online) {
      setPill("online", "Online");
      el.status.textContent = "Online";
      el.guilds.textContent = formatCount(data.guild_count);
      el.members.textContent = formatCount(data.member_count);
      el.uptime.textContent = formatUptime(data.uptime_seconds);
      liveNote.textContent = data.username
        ? "Live status from " + data.username + "."
        : "Live status from your running bot.";
    } else {
      setPill("offline", "Offline");
      el.status.textContent = "Offline";
      el.guilds.textContent = "—";
      el.members.textContent = "—";
      el.uptime.textContent = "—";
      liveNote.textContent = "The bot is not currently connected.";
    }
  }

  function poll() {
    fetch("/api/status", { cache: "no-store" })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(render)
      .catch(function () {
        setPill("offline", "Offline");
        el.status.textContent = "Offline";
        liveNote.textContent = "Couldn't reach the status endpoint.";
      });
  }

  poll();
  setInterval(poll, POLL_MS);
})();
