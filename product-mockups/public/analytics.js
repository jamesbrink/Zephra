(() => {
  const origin = "https://zephra.urandom.io";
  if (
    location.origin !== origin ||
    location.pathname !== "/" ||
    window.zephraAnalytics
  )
    return;
  window.zephraAnalytics = true;
  const id = "G-XMF63TG8ZY";
  window.dataLayer = window.dataLayer || [];
  function gtag() {
    // Google tag commands use its documented arguments-object queue format.
    // oxlint-disable-next-line prefer-rest-params
    window.dataLayer.push(arguments);
  }
  let referrer = "";
  try {
    referrer = new URL(document.referrer).origin;
  } catch {
    /* Direct visit. */
  }
  gtag("consent", "default", {
    analytics_storage: "granted",
    ad_storage: "denied",
    ad_user_data: "denied",
    ad_personalization: "denied",
  });
  gtag("js", new Date());
  gtag("set", { page_location: `${origin}/`, page_referrer: referrer });
  gtag("config", id, {
    send_page_view: false,
    allow_google_signals: false,
    allow_ad_personalization_signals: false,
    cookie_domain: "zephra.urandom.io",
    cookie_prefix: "zephra",
    cookie_flags: "SameSite=Lax;Secure",
  });
  gtag("event", "page_view", { page_title: document.title });
  document.addEventListener("click", (event) => {
    const anchor =
      event.target instanceof Element ? event.target.closest("a[href]") : null;
    if (!anchor) return;
    const url = new URL(anchor.href);
    if (
      url.origin !== "https://zephra-assets.urandom.io" ||
      !/^\/releases\/Zephra-[\d.]+-[\d.]+\.dmg$/.test(url.pathname)
    )
      return;
    gtag("event", "file_download", {
      file_extension: "dmg",
      file_name: url.pathname.split("/").pop(),
      link_url: url.origin + url.pathname,
      link_text: "Download for Mac",
    });
  });
  const script = document.createElement("script");
  script.async = true;
  script.src = `https://www.googletagmanager.com/gtag/js?id=${id}`;
  document.head.appendChild(script);
})();
