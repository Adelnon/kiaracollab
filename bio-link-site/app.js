// Onelink landing page — front-end flourishes only. No backend calls; the
// handle checker is a client-side validity hint, not a real availability lookup.

(function () {
  "use strict";

  // Rotating word in the hero headline.
  var rotator = document.getElementById("rotator");
  var words = ["you", "your brand", "your shop", "your vibe", "your work"];
  var i = 0;
  if (rotator) {
    setInterval(function () {
      i = (i + 1) % words.length;
      rotator.style.opacity = "0";
      setTimeout(function () {
        rotator.textContent = words[i];
        rotator.style.opacity = "1";
      }, 180);
    }, 2200);
    rotator.style.transition = "opacity 0.18s ease";
  }

  // Handle field: light client-side validation and friendly feedback.
  var form = document.getElementById("claim");
  var input = document.getElementById("handle");
  var note = document.getElementById("claim-note");
  var valid = /^[a-zA-Z0-9-]{2,24}$/;

  function setNote(msg, cls) {
    if (!note) return;
    note.textContent = msg;
    note.className = "claim-note" + (cls ? " " + cls : "");
  }

  if (input) {
    input.addEventListener("input", function () {
      var v = input.value.trim();
      if (!v) {
        setNote("Handles are 2–24 characters — letters, numbers, dashes.", "");
      } else if (valid.test(v)) {
        setNote("onelink.to/" + v + " looks good — claim it to reserve it.", "ok");
      } else {
        setNote("Use 2–24 letters, numbers or dashes only.", "bad");
      }
    });
  }

  if (form) {
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      var v = (input && input.value.trim()) || "";
      if (!valid.test(v)) {
        setNote("Pick a handle first — 2–24 letters, numbers or dashes.", "bad");
        if (input) input.focus();
        return;
      }
      setNote("Nice — onelink.to/" + v + " is yours to set up. (Demo: no account is created.)", "ok");
    });
  }
})();
