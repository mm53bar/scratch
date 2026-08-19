import { Controller } from "@hotwired/stimulus"

// Submits a form a short while after typing stops, so results update as you
// type without a request per keystroke.
//
// Deliberately server-side rather than filtering the rendered DOM the way a
// smaller list can: this searches ~2,000 tracks, and shipping all of them to
// the browser to filter locally would cost more than the round trip saves.
export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
