// Inhalte der Shorts. Jede Szene = eine Texttafel.
// Fakten-Stand: 18.11.2026 (Quellen in ../README.md). Vor dem Upload nochmal prüfen!

export type Scene = {
  kicker?: string; // kleine Zeile oben
  headline: string; // große Zeile
  sub?: string; // Erklärzeile unten
  accent?: "pink" | "cyan" | "orange";
  seconds?: number; // Standard: 3
};

export type ShortData = {
  id: string;
  title: string;
  scenes: Scene[];
};

export const SHORTS: ShortData[] = [
  {
    id: "Short1-Metacritic99",
    title: "GTA 6 hat 99 auf Metacritic",
    scenes: [
      { kicker: "BREAKING", headline: "99 von 100", sub: "Der Metacritic-Wert von GTA 6", accent: "pink", seconds: 2.5 },
      { headline: "Gleichstand mit Ocarina of Time", sub: "Das bisher bestbewertete Spiel aller Zeiten", accent: "cyan" },
      { headline: "0 gemischte Reviews", sub: "Keine einzige negative Kritik bei Metacritic", accent: "orange" },
      { kicker: "ABER", headline: "Nur 30 FPS", sub: "Auf allen Konsolen, auch auf der PS5 Pro", accent: "pink" },
      { headline: "Realismus pur", sub: "Autos gehen schnell kaputt, Reparaturen kosten Geld", accent: "cyan" },
      { kicker: "DEINE MEINUNG?", headline: "Verdient oder überbewertet?", sub: "Schreib es in die Kommentare", accent: "orange", seconds: 3.5 },
    ],
  },
  {
    id: "Short2-LaunchGuide",
    title: "GTA 6: Alles vor dem Launch",
    scenes: [
      { kicker: "MORGEN", headline: "GTA 6 ist da", sub: "Alles, was du jetzt wissen musst", accent: "pink", seconds: 2.5 },
      { kicker: "WANN?", headline: "19. November", sub: "Um Mitternacht Ortszeit", accent: "cyan" },
      { kicker: "WO?", headline: "PS5 & Xbox Series X|S", sub: "Die PC-Version kommt später", accent: "orange" },
      { kicker: "SPEICHER", headline: "Bis zu 212 GB", sub: "Jetzt Platz schaffen!", accent: "pink" },
      { kicker: "PREIS (USA)", headline: "79,99 $ / 99,99 $", sub: "Standard oder Ultimate Edition", accent: "cyan" },
      { kicker: "BONUS", headline: "Vintage Vice City Pack", sub: "Gibt es für Vorbesteller dazu", accent: "orange" },
      { headline: "Folgen für mehr GTA 6", sub: "Jeden Tag neue Tipps", accent: "pink", seconds: 3.5 },
    ],
  },
  {
    id: "Short3-KeinOnline",
    title: "GTA 6 Online kommt nicht zum Launch",
    scenes: [
      { kicker: "WICHTIG", headline: "Kein Online-Modus", sub: "Zum Launch von GTA 6", accent: "pink", seconds: 2.5 },
      { headline: "Erstmal nur Story", sub: "GTA 6 startet als reines Einzelspieler-Spiel", accent: "cyan" },
      { kicker: "LAUT BLOOMBERG", headline: "GTA 6 Online kommt 2027", sub: "Das ist noch nicht offiziell bestätigt", accent: "orange" },
      { headline: "Gut oder schlecht?", sub: "Ab in die Kommentare", accent: "pink", seconds: 3.5 },
    ],
  },
];

export const FPS = 30;
export const sceneFrames = (s: Scene) => Math.round((s.seconds ?? 3) * FPS);
export const totalFrames = (d: ShortData) => d.scenes.reduce((a, s) => a + sceneFrames(s), 0);
