import React from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  Sequence,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Scene, sceneFrames, ShortData } from "./shorts";

const COLORS = {
  pink: "#ff3d8b",
  cyan: "#2de2e6",
  orange: "#ff9f1c",
};

// Eigener Sunset-/Neon-Look (keine Rockstar-Logos oder Grafiken).
const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const shift = Math.sin(frame / 60) * 8;
  return (
    <AbsoluteFill
      style={{
        background: `linear-gradient(${170 + shift}deg, #12002b 0%, #3a0a5e 40%, #b3175f 72%, #ff8a3d 100%)`,
      }}
    >
      {/* Sonne */}
      <div
        style={{
          position: "absolute",
          left: 540 - 330,
          top: 1180,
          width: 660,
          height: 660,
          borderRadius: "50%",
          background: "linear-gradient(180deg, #ffd36e 0%, #ff4f8b 100%)",
          opacity: 0.55,
          filter: "blur(2px)",
        }}
      />
      {/* Horizontlinien */}
      {new Array(9).fill(0).map((_, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: 1500 + i * 48 + ((frame * 1.5) % 48),
            height: 4,
            background: "rgba(18,0,43,0.55)",
          }}
        />
      ))}
      <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 35%, transparent 30%, rgba(0,0,0,0.55) 100%)" }} />
    </AbsoluteFill>
  );
};

const SceneCard: React.FC<{ scene: Scene }> = ({ scene }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const color = COLORS[scene.accent ?? "pink"];
  const pop = spring({ frame, fps, config: { damping: 12, mass: 0.6 } });
  const subIn = interpolate(frame, [8, 20], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const dur = sceneFrames(scene);
  const out = interpolate(frame, [dur - 6, dur], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  return (
    <AbsoluteFill
      style={{
        justifyContent: "center",
        alignItems: "center",
        padding: "0 90px",
        textAlign: "center",
        fontFamily: "Impact, 'Arial Black', sans-serif",
        opacity: out,
      }}
    >
      {scene.kicker ? (
        <div
          style={{
            background: color,
            color: "#12002b",
            fontSize: 54,
            padding: "10px 34px",
            borderRadius: 14,
            letterSpacing: 4,
            marginBottom: 40,
            transform: `scale(${pop})`,
          }}
        >
          {scene.kicker}
        </div>
      ) : null}
      <div
        style={{
          color: "white",
          fontSize: scene.headline.length > 18 ? 104 : 140,
          lineHeight: 1.05,
          textTransform: "uppercase",
          transform: `scale(${0.6 + 0.4 * pop}) rotate(${(1 - pop) * -4}deg)`,
          textShadow: `0 0 30px ${color}, 6px 6px 0 #12002b`,
        }}
      >
        {scene.headline}
      </div>
      {scene.sub ? (
        <div
          style={{
            marginTop: 50,
            color: "white",
            fontFamily: "'Arial', sans-serif",
            fontWeight: 700,
            fontSize: 52,
            lineHeight: 1.25,
            opacity: subIn,
            transform: `translateY(${(1 - subIn) * 30}px)`,
            background: "rgba(18,0,43,0.6)",
            padding: "18px 30px",
            borderRadius: 18,
          }}
        >
          {scene.sub}
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

export const Short: React.FC<{ data: ShortData }> = ({ data }) => {
  let from = 0;
  return (
    <AbsoluteFill>
      <Background />
      {data.scenes.map((scene, i) => {
        const d = sceneFrames(scene);
        const el = (
          <Sequence key={i} from={from} durationInFrames={d}>
            <SceneCard scene={scene} />
          </Sequence>
        );
        from += d;
        return el;
      })}
    </AbsoluteFill>
  );
};
