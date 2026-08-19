import { Controller } from "@hotwired/stimulus"

// Reloads the surrounding turbo-frame on a timer.
//
// Attach it to something *inside* the frame that only exists while there is
// something to watch. When the frame reloads and that thing is gone, this
// disconnects and the polling stops — no condition to remember to check.
export default class extends Controller {
  static values = { interval: { type: Number, default: 2000 } }

  connect() {
    this.frame = this.element.closest("turbo-frame")
    if (!this.frame) return

    this.timer = setInterval(() => {
      // A backgrounded tab is not watching, and waking every two seconds to
      // ask anyway is someone's battery.
      if (document.visibilityState === "visible") this.frame.reload()
    }, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
