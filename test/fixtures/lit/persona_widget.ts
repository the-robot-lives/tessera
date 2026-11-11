import { LitElement, html, css } from "lit";
import { customElement, property, state } from "lit/decorators.js";

/**
 * A persona card widget. This doc comment mentions
 * @property({ type: Number }) ghost = 1; which must NOT be extracted.
 */
@customElement("persona-widget")
export class PersonaWidget extends LitElement {
  static styles = css`
    :host { display: block; }
    .card { padding: 8px; }
  `;

  @property({ type: String, attribute: "display-name", reflect: true })
  displayName = "Anonymous";

  @property({ type: Number }) clickCount = 0;

  @property({ type: Boolean, reflect: true }) disabled = false;

  @property({ type: Array }) tagList: string[] = [];

  @property({ type: Object, attribute: false })
  filters: Record<string, string> = {};

  @property({
    type: String,
    attribute: "tone",
    converter: { fromAttribute: (value: string | null) => value ?? "neutral" },
  })
  tone = "neutral";

  @property() label: string;

  @property({ type: String }) sessionId = crypto.randomUUID();

  @state() open = false;

  @state() internalCount = 0;

  render() {
    const url = "https://example.com/docs"; // a URL inside a string is not a comment
    return html`
      <div class="card" data-url=${url}>
        <slot name="header"></slot>
        <slot></slot>
        <slot name="footer" />
      </div>
    `;
  }

  private select() {
    this.dispatchEvent(
      new CustomEvent("persona-select", {
        detail: { personaId: "p1", clickCount: 2, active: true },
        bubbles: true,
        composed: true,
      })
    );
  }

  private focusChanged() {
    this.dispatchEvent(new CustomEvent("focusChanged", { detail: { source: this.displayName } }));
  }

  private close() {
    // @property({ type: Number }) commentedOut = 9;
    this.dispatchEvent(new CustomEvent("close"));
  }
}