// Paste the App Store link here once the app is live, e.g. "https://apps.apple.com/app/id1234567890".
var STORM_STITCH_APP_STORE = "";

(function () {
  if (!STORM_STITCH_APP_STORE) return;
  document.querySelectorAll(".js-store").forEach(function (el) {
    el.href = STORM_STITCH_APP_STORE;
    el.removeAttribute("aria-disabled");
    el.innerHTML = "<span>Download<small>on the App Store</small></span>";
  });
})();
