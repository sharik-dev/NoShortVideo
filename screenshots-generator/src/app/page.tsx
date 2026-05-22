"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { toPng } from "html-to-image";

// ─── Canvas dimensions ────────────────────────────────────────────────────────
const W = 1320;
const H = 2868;
const RATIO = H / W;

// ─── iPhone mockup measurements (pre-measured from mockup.png) ────────────────
const MK_W = 1022, MK_H = 2082;
const SC_L = (52 / MK_W) * 100;
const SC_T = (46 / MK_H) * 100;
const SC_W = (918 / MK_W) * 100;
const SC_H = (1990 / MK_H) * 100;
const SC_RX = (126 / 918) * 100;
const SC_RY = (126 / 1990) * 100;

// ─── Export sizes (Apple required) ───────────────────────────────────────────
const SIZES = [
  { label: '6.9"', w: 1320, h: 2868 },
  { label: '6.5"', w: 1284, h: 2778 },
  { label: '6.3"', w: 1206, h: 2622 },
  { label: '6.1"', w: 1125, h: 2436 },
] as const;

// ─── Image preloading ─────────────────────────────────────────────────────────
// All images are converted to base64 data URIs so html-to-image never re-fetches
// them during SVG serialization (which fails non-deterministically).
const IMAGE_PATHS = [
  "/mockup.png",
  "/app-icon.png",
  "/screenshots/home.png",
  "/screenshots/gauge.png",
  "/screenshots/settings.png",
  "/screenshots/library.png",
  "/screenshots/browser.png",
];

const cache: Record<string, string> = {};

async function preload() {
  await Promise.all(
    IMAGE_PATHS.map(async (path) => {
      try {
        const res = await fetch(path);
        if (!res.ok) return;
        const blob = await res.blob();
        cache[path] = await new Promise<string>((resolve) => {
          const reader = new FileReader();
          reader.onloadend = () => resolve(reader.result as string);
          reader.readAsDataURL(blob);
        });
      } catch {
        // Missing screenshot — placeholder shown instead
      }
    })
  );
}

const img = (p: string): string => cache[p] ?? "";
const has = (p: string): boolean => !!cache[p];

// ─── Design tokens ────────────────────────────────────────────────────────────
const RED = "#E8001C";
const RED_GLOW = "rgba(232,0,28,0.58)";
const FONT = "var(--font-inter), system-ui, -apple-system, sans-serif";

// ─── Phone component ──────────────────────────────────────────────────────────
function Phone({
  src,
  children,
  style,
}: {
  src: string;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}) {
  return (
    <div style={{ position: "relative", aspectRatio: `${MK_W}/${MK_H}`, ...style }}>
      {has("/mockup.png") && (
        <img
          src={img("/mockup.png")}
          alt=""
          style={{ display: "block", width: "100%", height: "100%" }}
          draggable={false}
        />
      )}
      <div
        style={{
          position: "absolute",
          zIndex: 10,
          overflow: "hidden",
          left: `${SC_L}%`,
          top: `${SC_T}%`,
          width: `${SC_W}%`,
          height: `${SC_H}%`,
          borderRadius: `${SC_RX}% / ${SC_RY}%`,
          background: "#000",
        }}
      >
        {has(src) ? (
          <img
            src={img(src)}
            alt=""
            style={{
              display: "block",
              width: "100%",
              height: "100%",
              objectFit: "cover",
              objectPosition: "top",
            }}
            draggable={false}
          />
        ) : (
          children
        )}
      </div>
    </div>
  );
}

// ─── Slide 1: Hero ────────────────────────────────────────────────────────────
function Slide1({ cw = W }: { cw?: number }) {
  const ch = cw * RATIO;
  return (
    <div
      style={{
        width: cw,
        height: ch,
        position: "relative",
        overflow: "hidden",
        background: "#06000A",
        fontFamily: FONT,
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 110% 52% at 50% -8%, rgba(232,0,28,0.62) 0%, transparent 62%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 80% 45% at 50% 108%, rgba(100,0,20,0.38) 0%, transparent 68%)",
        }}
      />

      {has("/app-icon.png") && (
        <img
          src={img("/app-icon.png")}
          alt="icon"
          style={{
            position: "absolute",
            width: cw * 0.21,
            height: cw * 0.21,
            borderRadius: cw * 0.047,
            top: cw * 0.13,
            left: "50%",
            transform: "translateX(-50%)",
            zIndex: 5,
            boxShadow: `0 0 ${cw * 0.09}px ${RED_GLOW}, 0 ${cw * 0.025}px ${cw * 0.07}px rgba(0,0,0,0.85)`,
          }}
          draggable={false}
        />
      )}

      <div
        style={{
          position: "absolute",
          top: cw * 0.44,
          left: 0,
          right: 0,
          textAlign: "center",
          zIndex: 5,
          padding: `0 ${cw * 0.09}px`,
        }}
      >
        <div
          style={{
            fontSize: cw * 0.027,
            fontWeight: 700,
            letterSpacing: "0.15em",
            textTransform: "uppercase",
            color: RED,
            marginBottom: cw * 0.028,
          }}
        >
          No Short Video
        </div>
        <div
          style={{
            fontSize: cw * 0.098,
            fontWeight: 900,
            lineHeight: 0.91,
            color: "#fff",
          }}
        >
          Zero Shorts.
          <br />
          Zero Distractions.
        </div>
      </div>

      <Phone
        src="/screenshots/home.png"
        style={{
          width: cw * 0.83,
          position: "absolute",
          bottom: -cw * 0.14,
          left: "50%",
          transform: "translateX(-50%)",
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            background:
              "linear-gradient(180deg, #0A0000 0%, #260009 50%, #080002 100%)",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: "8%",
          }}
        >
          <div
            style={{
              fontSize: "13%",
              fontWeight: 900,
              color: RED,
              letterSpacing: "0.08em",
              fontFamily: FONT,
            }}
          >
            NO SHORTS
          </div>
          <div
            style={{
              width: "55%",
              height: "2.5px",
              background: `linear-gradient(90deg, ${RED}, transparent)`,
              borderRadius: 2,
            }}
          />
          <div
            style={{
              fontSize: "6%",
              color: "rgba(255,255,255,0.35)",
              fontFamily: FONT,
            }}
          >
            Clean browsing. Always.
          </div>
        </div>
      </Phone>
    </div>
  );
}

// ─── Slide 2: Session Gauge ───────────────────────────────────────────────────
function Slide2({ cw = W }: { cw?: number }) {
  const ch = cw * RATIO;
  return (
    <div
      style={{
        width: cw,
        height: ch,
        position: "relative",
        overflow: "hidden",
        background: "#060009",
        fontFamily: FONT,
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 120% 60% at 115% 52%, rgba(255,75,0,0.32) 0%, transparent 62%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 70% 50% at -12% 48%, rgba(220,0,28,0.18) 0%, transparent 58%)",
        }}
      />

      <div
        style={{
          position: "absolute",
          top: cw * 0.15,
          left: cw * 0.1,
          zIndex: 5,
        }}
      >
        <div
          style={{
            fontSize: cw * 0.026,
            fontWeight: 700,
            letterSpacing: "0.15em",
            textTransform: "uppercase",
            color: RED,
            marginBottom: cw * 0.026,
          }}
        >
          Focus Timer
        </div>
        <div
          style={{
            fontSize: cw * 0.098,
            fontWeight: 900,
            lineHeight: 0.91,
            color: "#fff",
          }}
        >
          Know when
          <br />
          to stop.
        </div>
      </div>

      <Phone
        src="/screenshots/gauge.png"
        style={{
          width: cw * 0.85,
          position: "absolute",
          bottom: -cw * 0.1,
          right: -cw * 0.07,
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            background: "linear-gradient(180deg, #080008 0%, #160014 100%)",
            position: "relative",
          }}
        >
          <div
            style={{
              position: "absolute",
              left: "7%",
              top: "18%",
              bottom: "14%",
              width: "6.5%",
              background: "rgba(255,255,255,0.07)",
              borderRadius: 999,
              overflow: "hidden",
            }}
          >
            <div
              style={{
                position: "absolute",
                bottom: 0,
                width: "100%",
                height: "65%",
                background: "linear-gradient(0deg, #FF2200, #FFAA00)",
                borderRadius: 999,
              }}
            />
          </div>
          <div
            style={{
              position: "absolute",
              top: "14%",
              left: "18%",
              right: "5%",
              height: "72%",
              background: "rgba(255,255,255,0.03)",
              borderRadius: "3%",
            }}
          />
        </div>
      </Phone>
    </div>
  );
}

// ─── Slide 3: Daily Limit ─────────────────────────────────────────────────────
function Slide3({ cw = W }: { cw?: number }) {
  const ch = cw * RATIO;
  return (
    <div
      style={{
        width: cw,
        height: ch,
        position: "relative",
        overflow: "hidden",
        background: "#070008",
        fontFamily: FONT,
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 95% 55% at 22% 115%, rgba(232,0,28,0.38) 0%, transparent 60%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 70% 48% at 85% -12%, rgba(110,0,170,0.24) 0%, transparent 55%)",
        }}
      />

      <div
        style={{
          position: "absolute",
          top: cw * 0.15,
          left: cw * 0.1,
          zIndex: 5,
        }}
      >
        <div
          style={{
            fontSize: cw * 0.026,
            fontWeight: 700,
            letterSpacing: "0.15em",
            textTransform: "uppercase",
            color: RED,
            marginBottom: cw * 0.026,
          }}
        >
          Daily limits
        </div>
        <div
          style={{
            fontSize: cw * 0.098,
            fontWeight: 900,
            lineHeight: 0.91,
            color: "#fff",
          }}
        >
          Your time.
          <br />
          Your rules.
        </div>
      </div>

      <Phone
        src="/screenshots/settings.png"
        style={{
          width: cw * 0.8,
          position: "absolute",
          bottom: -cw * 0.1,
          left: "50%",
          transform: "translateX(-50%)",
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            background: "linear-gradient(180deg, #0A0010 0%, #130016 100%)",
          }}
        >
          {(
            [
              { label: "Daily Limit", value: "2h", color: RED },
              { label: "Session Gauge", value: "ON", color: "#00CC66" },
              {
                label: "Language",
                value: "EN",
                color: "rgba(255,255,255,0.45)",
              },
            ] as const
          ).map((row, i) => (
            <div
              key={i}
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                padding: "3.5% 8%",
                borderBottom: "1px solid rgba(255,255,255,0.06)",
                marginTop: i === 0 ? "20%" : 0,
              }}
            >
              <span
                style={{
                  color: "rgba(255,255,255,0.62)",
                  fontSize: "5.2%",
                  fontFamily: FONT,
                }}
              >
                {row.label}
              </span>
              <span
                style={{
                  color: row.color,
                  fontWeight: 700,
                  fontSize: "5.2%",
                  fontFamily: FONT,
                }}
              >
                {row.value}
              </span>
            </div>
          ))}
        </div>
      </Phone>
    </div>
  );
}

// ─── Slide 4: Library ─────────────────────────────────────────────────────────
function Slide4({ cw = W }: { cw?: number }) {
  const ch = cw * RATIO;
  return (
    <div
      style={{
        width: cw,
        height: ch,
        position: "relative",
        overflow: "hidden",
        background: "#080004",
        fontFamily: FONT,
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 115% 55% at -8% 50%, rgba(232,0,28,0.22) 0%, transparent 62%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 90% 50% at 108% 92%, rgba(70,0,140,0.2) 0%, transparent 62%)",
        }}
      />

      <div
        style={{
          position: "absolute",
          top: cw * 0.11,
          left: 0,
          right: 0,
          textAlign: "center",
          zIndex: 5,
          padding: `0 ${cw * 0.08}px`,
        }}
      >
        <div
          style={{
            fontSize: cw * 0.026,
            fontWeight: 700,
            letterSpacing: "0.15em",
            textTransform: "uppercase",
            color: RED,
            marginBottom: cw * 0.026,
          }}
        >
          Your Library
        </div>
        <div
          style={{
            fontSize: cw * 0.098,
            fontWeight: 900,
            lineHeight: 0.91,
            color: "#fff",
          }}
        >
          Save the
          <br />
          good stuff.
        </div>
      </div>

      <Phone
        src="/screenshots/library.png"
        style={{
          width: cw * 0.82,
          position: "absolute",
          bottom: -cw * 0.1,
          left: "50%",
          transform: "translateX(-50%)",
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            background: "linear-gradient(180deg, #080003 0%, #190008 100%)",
          }}
        >
          {[0, 1, 2].map((i) => (
            <div
              key={i}
              style={{
                display: "flex",
                gap: "4%",
                padding: "3.5% 5%",
                borderBottom: "1px solid rgba(255,255,255,0.05)",
                marginTop: i === 0 ? "18%" : 0,
              }}
            >
              <div
                style={{
                  width: "30%",
                  aspectRatio: "16/9",
                  background: `linear-gradient(135deg, rgba(232,0,28,${0.25 + i * 0.15}), rgba(80,0,40,0.6))`,
                  borderRadius: "5%",
                  flexShrink: 0,
                }}
              />
              <div style={{ flex: 1, paddingTop: "1%" }}>
                <div
                  style={{
                    height: "18%",
                    background: "rgba(255,255,255,0.14)",
                    borderRadius: 3,
                    marginBottom: "8%",
                  }}
                />
                <div
                  style={{
                    height: "11%",
                    background: "rgba(255,255,255,0.06)",
                    borderRadius: 3,
                    width: "55%",
                  }}
                />
                <div
                  style={{
                    marginTop: "12%",
                    height: "4px",
                    background: "rgba(255,255,255,0.06)",
                    borderRadius: 2,
                    overflow: "hidden",
                  }}
                >
                  <div
                    style={{
                      height: "100%",
                      width: `${40 + i * 20}%`,
                      background: RED,
                      borderRadius: 2,
                    }}
                  />
                </div>
              </div>
            </div>
          ))}
        </div>
      </Phone>
    </div>
  );
}

// ─── Slide 5: Platforms ───────────────────────────────────────────────────────
function Slide5({ cw = W }: { cw?: number }) {
  const ch = cw * RATIO;
  const platforms = [
    { name: "YouTube", color: "#FF0000" },
    { name: "YT Music", color: "#FF1850" },
    { name: "Twitch", color: "#9147FF" },
  ];
  return (
    <div
      style={{
        width: cw,
        height: ch,
        position: "relative",
        overflow: "hidden",
        background: "#04000C",
        fontFamily: FONT,
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 105% 55% at 50% 12%, rgba(145,71,255,0.3) 0%, transparent 62%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 90% 50% at 50% 108%, rgba(232,0,28,0.28) 0%, transparent 62%)",
        }}
      />

      <div
        style={{
          position: "absolute",
          top: cw * 0.11,
          left: 0,
          right: 0,
          textAlign: "center",
          zIndex: 5,
          padding: `0 ${cw * 0.08}px`,
        }}
      >
        <div
          style={{
            fontSize: cw * 0.026,
            fontWeight: 700,
            letterSpacing: "0.15em",
            textTransform: "uppercase",
            color: RED,
            marginBottom: cw * 0.026,
          }}
        >
          All Platforms
        </div>
        <div
          style={{
            fontSize: cw * 0.098,
            fontWeight: 900,
            lineHeight: 0.91,
            color: "#fff",
          }}
        >
          YouTube,
          <br />
          Music & Twitch.
        </div>
      </div>

      {/* Platform color badges */}
      <div
        style={{
          position: "absolute",
          top: cw * 0.54,
          left: 0,
          right: 0,
          display: "flex",
          justifyContent: "center",
          gap: cw * 0.038,
          zIndex: 10,
        }}
      >
        {platforms.map((p) => (
          <div
            key={p.name}
            style={{
              padding: `${cw * 0.021}px ${cw * 0.038}px`,
              background: `${p.color}20`,
              border: `2px solid ${p.color}`,
              borderRadius: cw * 0.024,
              color: p.color,
              fontSize: cw * 0.029,
              fontWeight: 700,
              whiteSpace: "nowrap",
              fontFamily: FONT,
            }}
          >
            {p.name}
          </div>
        ))}
      </div>

      <Phone
        src="/screenshots/browser.png"
        style={{
          width: cw * 0.82,
          position: "absolute",
          bottom: -cw * 0.1,
          left: "50%",
          transform: "translateX(-50%)",
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            background: "linear-gradient(180deg, #04000C 0%, #0A0018 100%)",
          }}
        >
          <div
            style={{
              display: "flex",
              gap: "5%",
              padding: "4% 8%",
              marginTop: "25%",
            }}
          >
            {platforms.map((p, i) => (
              <div
                key={i}
                style={{
                  width: "28%",
                  aspectRatio: "1",
                  background: `${p.color}1A`,
                  border: `1.5px solid ${p.color}90`,
                  borderRadius: "20%",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <div
                  style={{
                    width: "48%",
                    height: "48%",
                    background: p.color,
                    borderRadius: "28%",
                    opacity: 0.8,
                  }}
                />
              </div>
            ))}
          </div>
        </div>
      </Phone>
    </div>
  );
}

// ─── Slide registry ───────────────────────────────────────────────────────────
const SLIDES = [Slide1, Slide2, Slide3, Slide4, Slide5] as const;
const SLIDE_NAMES = [
  "01-hero",
  "02-focus-timer",
  "03-daily-limit",
  "04-library",
  "05-platforms",
] as const;

// ─── Resize helper ────────────────────────────────────────────────────────────
async function resizeDataUrl(src: string, tw: number, th: number): Promise<string> {
  return new Promise((resolve) => {
    const image = new Image();
    image.onload = () => {
      const canvas = document.createElement("canvas");
      canvas.width = tw;
      canvas.height = th;
      canvas.getContext("2d")!.drawImage(image, 0, 0, tw, th);
      resolve(canvas.toDataURL("image/png"));
    };
    image.src = src;
  });
}

// ─── Preview card ─────────────────────────────────────────────────────────────
function SlideCard({ index, onExport }: { index: number; onExport: () => void }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);
  const [hovered, setHovered] = useState(false);
  const Slide = SLIDES[index];

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => {
      setScale(entry.contentRect.width / W);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <div
        ref={containerRef}
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        onClick={onExport}
        style={{
          position: "relative",
          width: "100%",
          aspectRatio: `${W}/${H}`,
          overflow: "hidden",
          borderRadius: 14,
          background: "#06000A",
          cursor: "pointer",
          boxShadow: hovered
            ? `0 8px 32px rgba(232,0,28,0.35), 0 0 0 1.5px ${RED}`
            : "0 4px 20px rgba(0,0,0,0.6)",
          transition: "box-shadow 0.2s",
        }}
      >
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            transformOrigin: "top left",
            transform: `scale(${scale})`,
            pointerEvents: "none",
          }}
        >
          <Slide cw={W} />
        </div>

        {hovered && (
          <div
            style={{
              position: "absolute",
              inset: 0,
              background: "rgba(0,0,0,0.52)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              borderRadius: 14,
            }}
          >
            <div
              style={{
                background: RED,
                color: "#fff",
                fontWeight: 700,
                fontSize: 13,
                padding: "9px 22px",
                borderRadius: 8,
                fontFamily: FONT,
                boxShadow: `0 4px 16px rgba(232,0,28,0.5)`,
              }}
            >
              Export PNG
            </div>
          </div>
        )}
      </div>

      <div
        style={{
          textAlign: "center",
          fontSize: 11,
          color: "rgba(255,255,255,0.3)",
          fontFamily: FONT,
          letterSpacing: "0.04em",
        }}
      >
        {SLIDE_NAMES[index]}
      </div>
    </div>
  );
}

// ─── Main page ────────────────────────────────────────────────────────────────
export default function ScreenshotsPage() {
  const [ready, setReady] = useState(false);
  const [sizeIdx, setSizeIdx] = useState(0);
  const [exporting, setExporting] = useState(false);
  const exportRefs = useRef<(HTMLDivElement | null)[]>([]);

  useEffect(() => {
    preload().then(() => setReady(true));
  }, []);

  const captureSlide = useCallback(async (index: number): Promise<string> => {
    const el = exportRefs.current[index];
    if (!el) throw new Error(`Export ref ${index} missing`);

    // Temporarily move on-screen so html-to-image can paint it
    el.style.left = "0px";
    el.style.opacity = "1";
    el.style.zIndex = "9998";

    try {
      const opts = { width: W, height: H, pixelRatio: 1, cacheBust: false };
      await toPng(el, opts); // warm-up: loads fonts lazily
      return await toPng(el, opts); // clean final capture
    } finally {
      el.style.left = "-9999px";
      el.style.opacity = "0";
      el.style.zIndex = "";
    }
  }, []);

  const exportSlide = useCallback(
    async (index: number) => {
      const size = SIZES[sizeIdx];
      const raw = await captureSlide(index);
      const dataUrl =
        size.w === W ? raw : await resizeDataUrl(raw, size.w, size.h);
      const a = document.createElement("a");
      a.href = dataUrl;
      a.download = `${SLIDE_NAMES[index]}-${size.w}x${size.h}.png`;
      a.click();
    },
    [sizeIdx, captureSlide]
  );

  const exportAll = useCallback(async () => {
    setExporting(true);
    const size = SIZES[sizeIdx];
    for (let i = 0; i < SLIDES.length; i++) {
      const raw = await captureSlide(i);
      const dataUrl =
        size.w === W ? raw : await resizeDataUrl(raw, size.w, size.h);
      const a = document.createElement("a");
      a.href = dataUrl;
      a.download = `${SLIDE_NAMES[i]}-${size.w}x${size.h}.png`;
      a.click();
      await new Promise((r) => setTimeout(r, 300));
    }
    setExporting(false);
  }, [sizeIdx, captureSlide]);

  if (!ready) {
    return (
      <div
        style={{
          minHeight: "100vh",
          background: "#06000A",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: FONT,
          color: "rgba(255,255,255,0.35)",
          fontSize: 16,
        }}
      >
        Loading…
      </div>
    );
  }

  return (
    <div
      style={{
        position: "relative",
        minHeight: "100vh",
        background: "#0A0A0F",
        padding: "32px 28px 48px",
        fontFamily: FONT,
      }}
    >
      {/* ── Toolbar ── */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 14,
          marginBottom: 36,
          flexWrap: "wrap",
        }}
      >
        <span
          style={{ fontSize: 19, fontWeight: 800, color: "#fff", letterSpacing: "-0.01em" }}
        >
          No Short Video <span style={{ color: RED }}>Screenshots</span>
        </span>
        <div style={{ flex: 1 }} />

        {SIZES.map((s, i) => (
          <button
            key={s.label}
            onClick={() => setSizeIdx(i)}
            style={{
              padding: "6px 13px",
              borderRadius: 7,
              background: sizeIdx === i ? RED : "rgba(255,255,255,0.07)",
              color: sizeIdx === i ? "#fff" : "rgba(255,255,255,0.45)",
              border:
                sizeIdx === i
                  ? `1px solid ${RED}`
                  : "1px solid rgba(255,255,255,0.1)",
              fontWeight: 600,
              fontSize: 13,
              cursor: "pointer",
              fontFamily: FONT,
              transition: "all 0.15s",
            }}
          >
            {s.label}
          </button>
        ))}

        <button
          onClick={exportAll}
          disabled={exporting}
          style={{
            padding: "8px 20px",
            borderRadius: 8,
            background: exporting ? "rgba(232,0,28,0.45)" : RED,
            color: "#fff",
            fontWeight: 700,
            fontSize: 14,
            cursor: exporting ? "default" : "pointer",
            border: "none",
            fontFamily: FONT,
            opacity: exporting ? 0.75 : 1,
            boxShadow: exporting ? "none" : `0 4px 18px rgba(232,0,28,0.4)`,
            transition: "all 0.15s",
          }}
        >
          {exporting ? "Exporting…" : "Export All"}
        </button>
      </div>

      {/* ── Info banner when screenshots are missing ── */}
      {!has("/screenshots/home.png") && (
        <div
          style={{
            marginBottom: 28,
            padding: "14px 20px",
            background: "rgba(232,0,28,0.08)",
            border: "1px solid rgba(232,0,28,0.25)",
            borderRadius: 10,
            fontSize: 13,
            color: "rgba(255,255,255,0.65)",
            lineHeight: 1.65,
            fontFamily: FONT,
          }}
        >
          <strong style={{ color: "#fff" }}>Placeholders actifs</strong> — Capture les écrans depuis le simulateur Xcode et place-les ici :{" "}
          <code
            style={{
              background: "rgba(255,255,255,0.08)",
              padding: "1px 6px",
              borderRadius: 4,
              fontSize: 12,
            }}
          >
            public/screenshots/home.png · gauge.png · settings.png · library.png · browser.png
          </code>
        </div>
      )}

      {/* ── Grid ── */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(210px, 1fr))",
          gap: 22,
        }}
      >
        {SLIDES.map((_, i) => (
          <SlideCard key={i} index={i} onExport={() => exportSlide(i)} />
        ))}
      </div>

      {/* ── Off-screen export elements ── */}
      {/* Positioned absolutely within this relative container.
          left: -9999px keeps them invisible; moved to left: 0 just before capture. */}
      <div
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          pointerEvents: "none",
          overflow: "visible",
        }}
      >
        {SLIDES.map((Slide, i) => (
          <div
            key={i}
            ref={(el) => {
              exportRefs.current[i] = el;
            }}
            style={{
              position: "absolute",
              top: 0,
              left: "-9999px",
              opacity: 0,
              width: W,
              height: H,
              fontFamily: FONT,
            }}
          >
            <Slide cw={W} />
          </div>
        ))}
      </div>
    </div>
  );
}
