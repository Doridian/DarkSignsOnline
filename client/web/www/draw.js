// The `Draw` command's coloured bands.
//
// A band is split into segments whose brightness is eased with a quarter
// sine, exactly as `basCommands.DrawSimple` does it. Reproducing the
// segmentation rather than using a smooth CSS gradient keeps the blocky look
// the original has.

/** What `DrawDividerWidth` is in the client. */
const DEFAULT_SEGMENTS = 24;

/** The client's easing: a quarter sine between the two ends. */
function sinLerp(from, to, value) {
  const offset = to < from ? from - value : value - from;
  const span = Math.abs(to - from);
  if (offset <= 0) return 0;
  if (offset >= span) return 1;
  return Math.sin((offset / span) * Math.PI * 0.5);
}

/** Fill `mult[a..b]` with the eased ramp, in whichever direction it runs. */
function ramp(mult, a, b) {
  const step = a > b ? -1 : 1;
  for (let n = a; step > 0 ? n <= b : n >= b; n += step) {
    mult[n] = sinLerp(a, b, n);
  }
}

function parse(css) {
  return [
    parseInt(css.slice(1, 3), 16),
    parseInt(css.slice(3, 5), 16),
    parseInt(css.slice(5, 7), 16),
  ];
}

/**
 * A CSS background for one band.
 *
 * `solid` is a flat colour; the rest are hard-stopped gradients, one stop
 * per segment.
 */
export function background(color, mode, segments) {
  if (mode === "solid" || !mode) {
    return color;
  }

  const count = segments > 0 ? segments : DEFAULT_SEGMENTS;
  const half = Math.floor(count / 2);
  const quarter = Math.floor(count / 4);
  const mult = new Array(count + 1).fill(0);

  switch (mode) {
    case "fadecenter":
      ramp(mult, half + 1, count);
      ramp(mult, half, 1);
      break;
    case "fadeinverse":
      ramp(mult, count, half + 1);
      ramp(mult, 1, half);
      break;
    case "fadein":
      ramp(mult, 1, count);
      break;
    case "fadeout":
      ramp(mult, count, 1);
      break;
    case "flow":
      ramp(mult, 1, quarter);
      ramp(mult, quarter * 2, quarter + 1);
      ramp(mult, quarter * 2 + 1, quarter * 3);
      ramp(mult, quarter * 4, quarter * 3 + 1);
      break;
    default:
      return color;
  }

  const [r, g, b] = parse(color);
  const stops = [];
  for (let n = 1; n <= count; n++) {
    const m = mult[n];
    const shade = `rgb(${Math.round(r * m)} ${Math.round(g * m)} ${Math.round(b * m)})`;
    const from = ((n - 1) / count) * 100;
    const to = (n / count) * 100;
    // Two stops per segment gives a hard edge rather than a blend.
    stops.push(`${shade} ${from.toFixed(3)}%`, `${shade} ${to.toFixed(3)}%`);
  }
  return `linear-gradient(90deg, ${stops.join(", ")})`;
}
