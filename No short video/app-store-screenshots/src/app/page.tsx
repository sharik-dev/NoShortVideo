"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import { toPng } from "html-to-image";

// ─── Canvas dimensions (design at largest, scale for export) ───────────────
const W = 1320;
const H = 2868;

const SIZES = [
  { label: '6.9"', w: 1320, h: 2868 },
  { label: '6.5"', w: 1284, h: 2778 },
  { label: '6.3"', w: 1206, h: 2622 },
  { label: '6.1"', w: 1125, h: 2436 },
] as const;

// ─── Phone mockup constants ────────────────────────────────────────────────
const MK_W = 1022;
const MK_H = 2082;
const SC_L = (52 / MK_W) * 100;
const SC_T = (46 / MK_H) * 100;
const SC_W = (918 / MK_W) * 100;
const SC_H = (1990 / MK_H) * 100;
const SC_RX = (126 / 918) * 100;
const SC_RY = (126 / 1990) * 100;

// ─── Image preloader ──────────────────────────────────────────────────────
const IMAGE_PATHS = [
  "/mockup.png",
  "/app-icon.png",
  "/screenshots/en/home.png",
  "/screenshots/en/player.png",
  "/screenshots/en/settings.png",
];
const imageCache: Record<string, string> = {};

async function preloadAllImages() {
  await Promise.all(
    IMAGE_PATHS.map(async (path) => {
      const resp = await fetch(path);
      const blob = await resp.blob();
      const dataUrl = await new Promise<string>((resolve) => {
        const reader = new FileReader();
        reader.onloadend = () => resolve(reader.result as string);
        reader.readAsDataURL(blob);
      });
      imageCache[path] = dataUrl;
    })
  );
}

function img(path: string): string {
  return imageCache[path] || path;
}

// ─── Phone component ──────────────────────────────────────────────────────
function Phone({ src, alt, style }: { src: string; alt: string; style?: React.CSSProperties }) {
  return (
    <div
      style={{
        position: "relative",
        aspectRatio: `${MK_W}/${MK_H}`,
        ...style,
      }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={img("/mockup.png")} alt="" style={{ display: "block", width: "100%", height: "100%" }} draggable={false} />
      <div
        style={{
          position: "absolute",
          left: `${SC_L}%`,
          top: `${SC_T}%`,
          width: `${SC_W}%`,
          height: `${SC_H}%`,
          borderRadius: `${SC_RX}% / ${SC_RY}%`,
          overflow: "hidden",
          zIndex: 1,
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={img(src)} alt={alt} style={{ display: "block", width: "100%", height: "100%", objectFit: "cover", objectPosition: "top" }} draggable={false} />
      </div>
    </div>
  );
}

// ─── Glow blob decorator ──────────────────────────────────────────────────
function Blob({ color, size, x, y, blur, opacity = 0.55 }: {
  color: string; size: number; x: string; y: string; blur: number; opacity?: number;
}) {
  return (
    <div style={{
      position: "absolute",
      left: x, top: y,
      width: size, height: size,
      borderRadius: "50%",
      background: color,
      filter: `blur(${blur}px)`,
      opacity,
      pointerEvents: "none",
      transform: "translate(-50%, -50%)",
    }} />
  );
}

// ─── Caption component ────────────────────────────────────────────────────
function Caption({ label, headline, align = "left", color = "#fff", accentColor = "#9145FF", canvasW = W }: {
  label: string;
  headline: React.ReactNode;
  align?: "left" | "center";
  color?: string;
  accentColor?: string;
  canvasW?: number;
}) {
  const labelSize = canvasW * 0.028;
  const headlineSize = canvasW * 0.092;
  return (
    <div style={{ textAlign: align, lineHeight: 1 }}>
      <div style={{
        fontSize: labelSize,
        fontWeight: 600,
        letterSpacing: "0.14em",
        textTransform: "uppercase",
        color: accentColor,
        marginBottom: canvasW * 0.022,
      }}>
        {label}
      </div>
      <div style={{
        fontSize: headlineSize,
        fontWeight: 800,
        color,
        lineHeight: 0.95,
        letterSpacing: "-0.01em",
      }}>
        {headline}
      </div>
    </div>
  );
}

// ─── Slide 1: Hero — "YouTube without the noise." ─────────────────────────
function Slide1() {
  const pad = W * 0.08;
  return (
    <div style={{
      width: W, height: H,
      background: "linear-gradient(160deg, #0D0D1A 0%, #110D24 55%, #0D0D1A 100%)",
      position: "relative",
      overflow: "hidden",
      fontFamily: "Syne, sans-serif",
    }}>
      {/* Background blobs */}
      <Blob color="#9145FF" size={900} x="20%" y="18%" blur={180} opacity={0.22} />
      <Blob color="#FF2E54" size={500} x="80%" y="12%" blur={120} opacity={0.18} />
      <Blob color="#9145FF" size={600} x="75%" y="85%" blur={140} opacity={0.15} />

      {/* App icon + brand strip */}
      <div style={{
        position: "absolute",
        top: pad * 1.6,
        left: pad,
        display: "flex",
        alignItems: "center",
        gap: W * 0.03,
      }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={img("/app-icon.png")}
          alt="No Short Video"
          style={{
            width: W * 0.1,
            height: W * 0.1,
            borderRadius: W * 0.022,
            boxShadow: "0 4px 24px rgba(145,69,255,0.5)",
          }}
          draggable={false}
        />
        <div style={{
          fontSize: W * 0.026,
          fontWeight: 700,
          color: "rgba(255,255,255,0.7)",
          letterSpacing: "0.02em",
        }}>
          No Short Video
        </div>
      </div>

      {/* Headline */}
      <div style={{
        position: "absolute",
        top: H * 0.21,
        left: pad,
        right: pad,
      }}>
        <Caption
          label="Focus browser"
          headline={<>YouTube<br />without<br />the noise.</>}
          accentColor="#9145FF"
        />
      </div>

      {/* Phone — centered, large */}
      <div style={{
        position: "absolute",
        bottom: 0,
        left: "50%",
        transform: "translateX(-50%) translateY(8%)",
        width: "84%",
      }}>
        <Phone src="/screenshots/en/home.png" alt="Home screen" />
      </div>

      {/* Subtle grid lines */}
      <div style={{
        position: "absolute", inset: 0, pointerEvents: "none",
        backgroundImage: "linear-gradient(rgba(145,69,255,0.04) 1px, transparent 1px), linear-gradient(90deg, rgba(145,69,255,0.04) 1px, transparent 1px)",
        backgroundSize: `${W * 0.1}px ${W * 0.1}px`,
      }} />
    </div>
  );
}

// ─── Slide 2: Player — "No Shorts. Ever again." ───────────────────────────
function Slide2() {
  const pad = W * 0.08;
  return (
    <div style={{
      width: W, height: H,
      background: "linear-gradient(170deg, #13001A 0%, #0D0D1A 40%, #1A0005 100%)",
      position: "relative",
      overflow: "hidden",
      fontFamily: "Syne, sans-serif",
    }}>
      {/* Background blobs */}
      <Blob color="#FF2E54" size={700} x="15%" y="75%" blur={160} opacity={0.2} />
      <Blob color="#9145FF" size={500} x="85%" y="25%" blur={120} opacity={0.2} />
      <Blob color="#FF2E54" size={400} x="70%" y="90%" blur={100} opacity={0.12} />

      {/* "Blocked" badge at top */}
      <div style={{
        position: "absolute",
        top: pad * 1.5,
        left: pad,
        display: "inline-flex",
        alignItems: "center",
        gap: W * 0.018,
        background: "rgba(255,46,84,0.15)",
        border: "1px solid rgba(255,46,84,0.4)",
        borderRadius: W * 0.05,
        padding: `${W * 0.012}px ${W * 0.028}px`,
      }}>
        <div style={{
          width: W * 0.016,
          height: W * 0.016,
          borderRadius: "50%",
          background: "#FF2E54",
          boxShadow: "0 0 8px #FF2E54",
        }} />
        <span style={{
          fontSize: W * 0.024,
          fontWeight: 700,
          color: "#FF2E54",
          letterSpacing: "0.08em",
          textTransform: "uppercase",
        }}>
          Shorts blocked
        </span>
      </div>

      {/* Headline */}
      <div style={{
        position: "absolute",
        top: H * 0.18,
        left: pad,
        right: pad,
      }}>
        <Caption
          label="Zero Shorts"
          headline={<>No Shorts.<br />Ever again.</>}
          accentColor="#FF2E54"
        />
      </div>

      {/* Two phones layered */}
      <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, height: "65%" }}>
        {/* Back phone */}
        <div style={{
          position: "absolute",
          left: "-6%",
          bottom: 0,
          width: "62%",
          transform: "rotate(-5deg) translateY(6%)",
          opacity: 0.45,
          filter: "blur(1px)",
        }}>
          <Phone src="/screenshots/en/home.png" alt="" />
        </div>
        {/* Front phone */}
        <div style={{
          position: "absolute",
          right: "-3%",
          bottom: 0,
          width: "78%",
          transform: "translateY(6%)",
        }}>
          <Phone src="/screenshots/en/player.png" alt="YouTube player" />
        </div>
      </div>

      {/* Grid lines */}
      <div style={{
        position: "absolute", inset: 0, pointerEvents: "none",
        backgroundImage: "linear-gradient(rgba(255,46,84,0.03) 1px, transparent 1px), linear-gradient(90deg, rgba(255,46,84,0.03) 1px, transparent 1px)",
        backgroundSize: `${W * 0.1}px ${W * 0.1}px`,
      }} />
    </div>
  );
}

// ─── Slide 3: Settings — "You set the rules." ─────────────────────────────
function Slide3() {
  const pad = W * 0.08;
  const features = [
    "Hide recommendations",
    "Blur thumbnails",
    "Grayscale mode",
    "Daily time limit",
    "Session gauge",
    "Save to Library",
  ];
  return (
    <div style={{
      width: W, height: H,
      background: "linear-gradient(155deg, #0D0D1A 0%, #0A0A16 50%, #101024 100%)",
      position: "relative",
      overflow: "hidden",
      fontFamily: "Syne, sans-serif",
    }}>
      {/* Background blobs */}
      <Blob color="#9145FF" size={800} x="85%" y="30%" blur={170} opacity={0.18} />
      <Blob color="#5B2DFF" size={500} x="10%" y="80%" blur={130} opacity={0.14} />

      {/* Headline */}
      <div style={{
        position: "absolute",
        top: H * 0.07,
        left: pad,
        right: pad,
      }}>
        <Caption
          label="Full control"
          headline={<>You set<br />the rules.</>}
          accentColor="#9145FF"
        />
      </div>

      {/* Feature pills */}
      <div style={{
        position: "absolute",
        top: H * 0.34,
        left: pad,
        right: pad,
        display: "flex",
        flexWrap: "wrap",
        gap: W * 0.025,
      }}>
        {features.map((f) => (
          <div key={f} style={{
            background: "rgba(145,69,255,0.12)",
            border: "1px solid rgba(145,69,255,0.35)",
            borderRadius: W * 0.06,
            padding: `${W * 0.014}px ${W * 0.032}px`,
            fontSize: W * 0.027,
            fontWeight: 600,
            color: "rgba(255,255,255,0.85)",
            whiteSpace: "nowrap",
          }}>
            {f}
          </div>
        ))}
      </div>

      {/* Phone — bottom right, angled */}
      <div style={{
        position: "absolute",
        bottom: 0,
        left: "50%",
        transform: "translateX(-50%) translateY(10%)",
        width: "82%",
      }}>
        <Phone src="/screenshots/en/settings.png" alt="Settings" />
      </div>

      {/* Grid lines */}
      <div style={{
        position: "absolute", inset: 0, pointerEvents: "none",
        backgroundImage: "linear-gradient(rgba(145,69,255,0.04) 1px, transparent 1px), linear-gradient(90deg, rgba(145,69,255,0.04) 1px, transparent 1px)",
        backgroundSize: `${W * 0.1}px ${W * 0.1}px`,
      }} />
    </div>
  );
}

// ─── Slide registry ───────────────────────────────────────────────────────
const SLIDES = [
  { id: "slide1", label: "01 · Hero", Component: Slide1 },
  { id: "slide2", label: "02 · Player", Component: Slide2 },
  { id: "slide3", label: "03 · Settings", Component: Slide3 },
];

// ─── Preview card ─────────────────────────────────────────────────────────
function SlidePreview({ slide, exportRef, onExport }: {
  slide: typeof SLIDES[number];
  exportRef: React.RefObject<HTMLDivElement | null>;
  onExport: () => void;
}) {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(0.2);

  useEffect(() => {
    const el = wrapperRef.current;
    if (!el) return;
    const obs = new ResizeObserver(() => {
      setScale(el.clientWidth / W);
    });
    obs.observe(el);
    return () => obs.disconnect();
  }, []);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <div
        ref={wrapperRef}
        style={{ width: "100%", aspectRatio: `${W}/${H}`, position: "relative", overflow: "hidden", borderRadius: 12, cursor: "pointer", boxShadow: "0 2px 20px rgba(0,0,0,0.4)" }}
        onClick={onExport}
        title="Click to export"
      >
        <div style={{ position: "absolute", top: 0, left: 0, transformOrigin: "top left", transform: `scale(${scale})`, width: W, height: H }}>
          <slide.Component />
        </div>
      </div>
      <div style={{ textAlign: "center", fontSize: 12, color: "#888", fontFamily: "monospace" }}>{slide.label}</div>

      {/* Offscreen export element */}
      <div
        ref={exportRef}
        style={{ position: "absolute", left: "-9999px", top: 0, width: W, height: H }}
      >
        <slide.Component />
      </div>
    </div>
  );
}

// ─── Main page ─────────────────────────────────────────────────────────────
export default function ScreenshotsPage() {
  const [ready, setReady] = useState(false);
  const [exporting, setExporting] = useState<string | null>(null);
  const [selectedSize, setSelectedSize] = useState<(typeof SIZES)[number]>(SIZES[0]);

  const slide1Ref = useRef<HTMLDivElement>(null);
  const slide2Ref = useRef<HTMLDivElement>(null);
  const slide3Ref = useRef<HTMLDivElement>(null);
  const refs = [slide1Ref, slide2Ref, slide3Ref];

  useEffect(() => {
    preloadAllImages().then(() => setReady(true));
  }, []);

  const exportSlide = useCallback(async (index: number, size: typeof SIZES[number]) => {
    const el = refs[index].current;
    if (!el) return;

    setExporting(SLIDES[index].id);
    el.style.left = "0px";
    el.style.zIndex = "-1";

    const opts = { width: W, height: H, pixelRatio: 1, cacheBust: true };

    try {
      await toPng(el, opts); // warm up
      const dataUrl = await toPng(el, opts);

      // Resize to target if needed
      let finalUrl = dataUrl;
      if (size.w !== W || size.h !== H) {
        const canvas = document.createElement("canvas");
        canvas.width = size.w;
        canvas.height = size.h;
        const ctx = canvas.getContext("2d")!;
        const imgEl = new Image();
        imgEl.src = dataUrl;
        await new Promise<void>((res) => { imgEl.onload = () => res(); });
        ctx.drawImage(imgEl, 0, 0, size.w, size.h);
        finalUrl = canvas.toDataURL("image/png");
      }

      const a = document.createElement("a");
      const label = SLIDES[index].id;
      a.href = finalUrl;
      a.download = `${String(index + 1).padStart(2, "0")}-${label}-${size.w}x${size.h}.png`;
      a.click();
    } finally {
      el.style.left = "-9999px";
      el.style.zIndex = "";
      setExporting(null);
    }
  }, [refs]);

  const exportAll = useCallback(async () => {
    for (let i = 0; i < SLIDES.length; i++) {
      await exportSlide(i, selectedSize);
      await new Promise((r) => setTimeout(r, 300));
    }
  }, [exportSlide, selectedSize]);

  if (!ready) {
    return (
      <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center", background: "#0D0D1A", color: "#fff", fontFamily: "Syne, sans-serif", fontSize: 18 }}>
        Loading images…
      </div>
    );
  }

  return (
    <div style={{ minHeight: "100vh", background: "#0a0a0f", color: "#fff", fontFamily: "Syne, sans-serif" }}>
      {/* Toolbar */}
      <div style={{
        position: "sticky", top: 0, zIndex: 100,
        background: "rgba(10,10,15,0.92)",
        backdropFilter: "blur(12px)",
        borderBottom: "1px solid rgba(145,69,255,0.2)",
        padding: "12px 24px",
        display: "flex", alignItems: "center", gap: 16, flexWrap: "wrap",
      }}>
        <span style={{ fontWeight: 800, fontSize: 16, color: "#9145FF" }}>No Short Video</span>
        <span style={{ color: "#444", fontSize: 14 }}>App Store Screenshots</span>

        <div style={{ marginLeft: "auto", display: "flex", gap: 10, alignItems: "center" }}>
          <select
            value={selectedSize.label}
            onChange={(e) => setSelectedSize(SIZES.find(s => s.label === e.target.value)!)}
            style={{ background: "#1a1a2e", color: "#fff", border: "1px solid rgba(145,69,255,0.3)", borderRadius: 6, padding: "4px 10px", fontSize: 13, fontFamily: "Syne, sans-serif" }}
          >
            {SIZES.map(s => <option key={s.label} value={s.label}>{s.label} — {s.w}×{s.h}</option>)}
          </select>

          <button
            onClick={exportAll}
            disabled={!!exporting}
            style={{
              background: exporting ? "#333" : "linear-gradient(135deg, #9145FF, #5B2DFF)",
              color: "#fff", border: "none", borderRadius: 8,
              padding: "8px 20px", fontSize: 13, fontWeight: 700,
              cursor: exporting ? "not-allowed" : "pointer",
              fontFamily: "Syne, sans-serif",
            }}
          >
            {exporting ? "Exporting…" : "Export all →"}
          </button>
        </div>
      </div>

      {/* Grid */}
      <div style={{
        display: "grid",
        gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))",
        gap: 32,
        padding: 32,
        maxWidth: 1400,
        margin: "0 auto",
      }}>
        {SLIDES.map((slide, i) => (
          <SlidePreview
            key={slide.id}
            slide={slide}
            exportRef={refs[i]}
            onExport={() => exportSlide(i, selectedSize)}
          />
        ))}
      </div>

      <p style={{ textAlign: "center", color: "#444", fontSize: 12, paddingBottom: 32 }}>
        Click a slide to export it at the selected resolution
      </p>
    </div>
  );
}
