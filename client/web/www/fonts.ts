// The fonts a script can name.
//
// Shared rather than kept with the renderer, because the worker measures
// text with the same table it is drawn with: `TextWidth` reports pixels, and
// a width measured in a font the machine does not have would not match the
// fallback that ends up on screen.

/** Family name to the CSS stack it is rendered with. */
export const FONT_STACK: Record<string, string> = {
  Impact: '"Impact", "Haettenschweiler", "Arial Narrow Bold", sans-serif',
  "Courier New": '"Courier New", "Liberation Mono", monospace',
  "Lucida Console": '"Lucida Console", "DejaVu Sans Mono", monospace',
  Verdana: '"Verdana", "DejaVu Sans", sans-serif',
  Wingdings: '"Wingdings", sans-serif',
  Webdings: '"Webdings", sans-serif',
};

export function fontFor(name: string): string {
  return FONT_STACK[name] ?? `"${name}", "DejaVu Sans", sans-serif`;
}
