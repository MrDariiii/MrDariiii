import React from "react";
import { Composition } from "remotion";
import { Short } from "./Short";
import { FPS, SHORTS, totalFrames } from "./shorts";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      {SHORTS.map((s) => (
        <Composition
          key={s.id}
          id={s.id}
          component={Short}
          durationInFrames={totalFrames(s)}
          fps={FPS}
          width={1080}
          height={1920}
          defaultProps={{ data: s }}
        />
      ))}
    </>
  );
};
