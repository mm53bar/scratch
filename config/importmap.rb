# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Positions the autocomplete dropdown — flipping and shifting it when it would
# overflow the viewport, which matters on a phone with the keyboard up.
# Vendored rather than pinned to a CDN: a self-hosted app should not need a
# third party to render its own search box.
pin "@floating-ui/dom", to: "floating-ui--dom.js"
