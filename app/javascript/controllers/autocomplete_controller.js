import { Controller } from "@hotwired/stimulus";
import { computePosition, offset, flip, shift, autoUpdate } from "@floating-ui/dom";

export default class extends Controller {
  static targets = ["input", "results", "suggestion", "clearButton", "searchIcon", "loadingIcon"];
  static values = {
    // Remote data configuration
    url: String, // URL for fetching suggestions from server
    minLength: { type: Number, default: 1 }, // Minimum characters before search triggers
    delay: { type: Number, default: 300 }, // Debounce delay in milliseconds for remote search requests (local searches are immediate, this applies to remote searches only)
    noResultsText: { type: String, default: "No results found" }, // Text displayed when no suggestions match, if empty, the results container will be closed instead of showing "no results" message
    loadingText: { type: String, default: "Searching..." }, // Text displayed during loading state
    separatorText: { type: String, default: "Search Results" }, // Text displayed in separator between local and remote results

    // Results and suggestions
    maxSuggestions: { type: Number, default: 10 }, // Maximum number of suggestions to display

    // Search behavior
    highlightMatches: { type: Boolean, default: true }, // Highlight matching text in suggestions
    autoFill: { type: Boolean, default: false }, // Automatically fill input with selected suggestion during keyboard navigation
    autoSelectFirst: { type: Boolean, default: false }, // Automatically select the first suggestion when user actively searches (not on focus/empty queries)
    submitOnSelect: { type: Boolean, default: true }, // Submit form when suggestion is selected
    clearOnEscape: { type: Boolean, default: true }, // Clear input when Escape key is pressed
    bubbleEscape: { type: Boolean, default: true }, // Allow Escape key to bubble up to parent elements
    freeSolo: { type: Boolean, default: true }, // Allow arbitrary values in input (when false, input resets on blur if no suggestion selected)

    // Local data search (alternative to remote URL)
    localData: { type: Array, default: [] }, // Array of data for client-side search
    searchKeys: { type: Array, default: ["title", "name", "label", "subtitle", "description", "email"] }, // Object properties to search in for local data
    matchStrategy: { type: String, default: "contains" }, // "prefix", "contains", "exact" - how to match search queries against local data, prefix will match the beginning of the text, contains will match any part of the text, exact will match the exact text

    // UI behavior
    searchOnFocus: { type: Boolean, default: false }, // Trigger search when input gains focus (even if empty)
    placement: { type: String, default: "bottom-start" }, // Floating UI placement for dropdown (e.g., "bottom-start", "top-end")
    offsetDistance: { type: Number, default: 8 }, // Distance in pixels from reference element
    anchor: { type: String, default: "input" }, // Element to position the dropdown relative to: "input" or "form" (default: "input")

    // Rendering and styling
    renderMode: { type: String, default: "popover" }, // "popover" for floating dropdown, "inline" for static positioning
    alwaysShow: { type: Boolean, default: false }, // Keep results container always visible (useful for command palettes)
    resultsClass: String, // CSS classes to override default results container styling
    suggestionClass: String, // Additional CSS classes for each suggestion item
    selectedClass: String, // CSS classes for selected suggestion item (defaults to "bg-neutral-50 dark:bg-neutral-800 selected", don't forget to include "selected")

    // Interaction behavior
    closeOnSelect: { type: Boolean, default: true }, // Close dropdown when suggestion is selected
    closeOnClickOutside: { type: Boolean, default: true }, // Close dropdown when clicking outside
    preserveSearchOnSelect: { type: Boolean, default: false }, // Preserve search state when selecting suggestions with URLs (don't clear input or close dropdown)

    // Action configuration
    selectAction: String, // Stimulus action to trigger on selection (e.g., "modal#close:prevent")
  };

  connect() {
    this.selectedIndex = -1;
    this.isOpen = false;
    this.searchTimeout = null;
    this.abortController = null;
    this.cleanupAutoUpdate = null;
    this.keyboardNavigating = false;
    this.lastSearchQuery = null;
    this.lastSelectedValue = null; // Track the last selected value for freeSolo behavior
    this.isLoading = false; // Track loading state to prevent flickering

    this.setupInputHandlers();
    this.setupKeyboardNavigation();
    this.setupClickOutside();
    this.setupMouseLeaveHandler();
    this.setupBlurHandler();
    this.setupFormSubmissionHandler();
    this.updateClearButtonVisibility();

    // Apply optional results container classes when provided (override all classes)
    if (this.hasResultsTarget && this.hasResultsClassValue && this.resultsClassValue) {
      this.resultsTarget.className = this.resultsClassValue;
    }

    // Show results container immediately if alwaysShow is enabled
    if (this.alwaysShowValue && this.hasResultsTarget) {
      this.resultsTarget.classList.remove("hidden");
      this.resultsTarget.classList.add("block");

      // Trigger initial search to populate results immediately
      setTimeout(() => {
        if (this.urlValue && this.localDataValue.length > 0) {
          // For hybrid search with empty query, only show local results (respects min-length for remote)
          this.performHybridSearch("");
        } else if (this.urlValue) {
          // Only fetch remote if min-length allows empty queries
          if ("".length >= this.minLengthValue) {
            this.fetchSuggestions("");
          }
        } else {
          this.searchLocalData("");
        }
      }, 0);
    }

    // Always add focus listener to handle showing results when input has text
    this.boundHandleInitialFocus = this.handleInitialFocus.bind(this);
    this.inputTarget.addEventListener("focus", this.boundHandleInitialFocus);

    // Handle cursor positioning for autofocused inputs with existing text
    this.handleAutofocusCursorPosition();

    // Dispatch connect event for customization
    const event = new CustomEvent("autocomplete:connect", {
      detail: { controller: this },
      bubbles: true,
    });
    document.dispatchEvent(event);
  }

  disconnect() {
    if (this.searchTimeout) clearTimeout(this.searchTimeout);
    if (this.abortController) this.abortController.abort();
    if (this.cleanupAutoUpdate) this.cleanupAutoUpdate();
    document.removeEventListener("mousedown", this.handleClickOutside);

    // Remove form submission listener
    if (this.boundHandleFormSubmit) {
      const form = this.inputTarget.closest("form");
      if (form) {
        form.removeEventListener("submit", this.boundHandleFormSubmit);
      }
    }

    // Remove keyboard navigation listeners
    if (this.boundHandleKeydown) {
      this.inputTarget.removeEventListener("keydown", this.boundHandleKeydown);
      if (this.hasResultsTarget) {
        this.resultsTarget.removeEventListener("keydown", this.boundHandleKeydown);
      }
    }

    // Remove focus and blur listeners
    if (this.boundHandleInitialFocus) {
      this.inputTarget.removeEventListener("focus", this.boundHandleInitialFocus);
    }
    if (this.boundHandleBlur) {
      this.inputTarget.removeEventListener("blur", this.boundHandleBlur);
    }

    // Remove mousedown listener from results container
    if (this.boundPreventFocusLoss && this.hasResultsTarget) {
      this.resultsTarget.removeEventListener("mousedown", this.boundPreventFocusLoss);
    }
  }

  setupInputHandlers() {
    // Store bound handler for potential removal by extension controllers
    this.boundHandleInput = this.handleInput.bind(this);
    this.inputTarget.addEventListener("input", this.boundHandleInput);
    this.inputTarget.setAttribute("autocomplete", "off");
    this.inputTarget.setAttribute("spellcheck", "false");
  }

  setupKeyboardNavigation() {
    // Store bound method references for cleanup
    this.boundHandleKeydown = this.handleKeydown.bind(this);

    this.inputTarget.addEventListener("keydown", this.boundHandleKeydown);

    // Add keyboard navigation to results container when it's focused
    if (this.hasResultsTarget) {
      this.resultsTarget.addEventListener("keydown", this.boundHandleKeydown);
    }
  }

  setupClickOutside() {
    this.handleClickOutside = (event) => {
      // Check if click is outside the entire autocomplete element
      if (!this.element.contains(event.target)) {
        // Don't close if alwaysShow is enabled - command palettes should stay open
        if (this.closeOnClickOutsideValue && !this.alwaysShowValue) {
          this.close();
        }
      }
    };
    if (this.closeOnClickOutsideValue) {
      document.addEventListener("mousedown", this.handleClickOutside);
    }
  }

  setupBlurHandler() {
    this.boundHandleBlur = this.handleBlur.bind(this);
    this.inputTarget.addEventListener("blur", this.boundHandleBlur);
  }

  setupFormSubmissionHandler() {
    const form = this.inputTarget.closest("form");
    if (form) {
      this.boundHandleFormSubmit = this.handleFormSubmit.bind(this);
      form.addEventListener("submit", this.boundHandleFormSubmit);
    }
  }

  setupMouseLeaveHandler() {
    if (this.hasResultsTarget) {
      this.resultsTarget.addEventListener("mouseleave", () => {
        // When mouse leaves results area during keyboard navigation,
        // ensure hover states are cleared
        if (this.keyboardNavigating) {
          this.clearHoverStates();
        }
      });

      this.resultsTarget.addEventListener("mouseenter", () => {
        // When mouse re-enters, allow normal hover behavior again
        // But only reset keyboard navigation if we're not actively using keyboard
        // This allows seamless transition between mouse and keyboard
        if (!this.keyboardNavigating) {
          this.updateKeyboardNavigationClass();
        }
      });

      // Prevent input from losing focus when clicking inside results container
      this.boundPreventFocusLoss = (event) => {
        // Prevent the default behavior that would cause input to lose focus
        event.preventDefault();
      };
      this.resultsTarget.addEventListener("mousedown", this.boundPreventFocusLoss);
    }
  }

  handleBlur() {
    // Cancel any pending search timeouts when losing focus (unless alwaysShow is enabled)
    if (!this.alwaysShowValue && this.searchTimeout) {
      clearTimeout(this.searchTimeout);
      this.searchTimeout = null;
      // Reset loading state if we were loading
      this.isLoading = false;
    }

    // Reset keyboard navigation state and selection when input loses focus
    // so a new interaction starts from the top.
    this.keyboardNavigating = false;
    this.selectedIndex = -1;

    // If freeSolo is false and the current input value doesn't match any selected suggestion,
    // reset the input to empty or the last selected value
    if (!this.freeSoloValue && this.inputTarget.value.trim() !== "") {
      const currentValue = this.inputTarget.value.trim();

      // Check if the current value matches the last selected value
      if (this.lastSelectedValue !== currentValue) {
        // Reset to empty or last selected value
        this.inputTarget.value = this.lastSelectedValue || "";
        this.updateClearButtonVisibility();
      }
    }
  }

  handleInitialFocus() {
    const currentValue = this.inputTarget.value.trim();

    if (currentValue) {
      // If the query hasn't changed and results container has content, just reopen it
      if (currentValue === this.lastSearchQuery && this.resultsTarget.innerHTML.trim() !== "") {
        this.open();
      } else {
        // Query has changed, trigger new search
        this.handleInput({ target: this.inputTarget });
      }
    } else {
      if (this.searchOnFocusValue) {
        // If search on focus is enabled, trigger a search with empty query
        if (this.urlValue && this.localDataValue.length > 0) {
          // For hybrid search with empty query, only show local results (respects min-length for remote)
          this.performHybridSearch("");
        } else if (this.urlValue) {
          // Only fetch remote if min-length allows empty queries
          if ("".length >= this.minLengthValue) {
            // Show loading state immediately for remote searches on focus
            this.showLoading();
            // Then fetch with delay, but make it cancelable
            this.searchTimeout = setTimeout(() => {
              // Only proceed if input is still empty (user hasn't started typing)
              if (this.inputTarget.value.trim() === "") {
                this.fetchSuggestions("");
              }
            }, this.delayValue);
          }
        } else {
          this.searchLocalData("");
        }
      }
    }
  }

  handleAutofocusCursorPosition() {
    // If the input has autofocus and contains text, position cursor at the end
    const hasAutofocus = this.inputTarget.hasAttribute("autofocus");
    const hasText = this.inputTarget.value.length > 0;

    if (hasAutofocus && hasText) {
      // Use setTimeout to ensure this runs after the browser's autofocus behavior
      setTimeout(() => {
        const length = this.inputTarget.value.length;
        this.inputTarget.setSelectionRange(length, length);
      }, 0);
    }
  }

  handleInput(event) {
    const query = event.target.value.trim();

    this.updateClearButtonVisibility();

    // Clear last query if current query is different
    if (query !== this.lastSearchQuery) {
      this.lastSearchQuery = null;
    }

    // Reset keyboard navigation state when new input triggers search
    this.keyboardNavigating = false;
    this.updateKeyboardNavigationClass();

    // When freeSolo is disabled, only enforce minLength for remote-only mode.
    // If local data exists, allow showing local results even with empty/short queries.
    if (
      !this.freeSoloValue &&
      this.urlValue &&
      this.localDataValue.length === 0 &&
      query.length < this.minLengthValue
    ) {
      this.close();
      return;
    }

    // Handle local-only searches immediately (no delay needed)
    if (!this.urlValue) {
      this.searchLocalData(query);
      return;
    }

    // Clear existing timeout for remote searches
    if (this.searchTimeout) clearTimeout(this.searchTimeout);

    // Respect minLength for remote-only searches (hybrid path handles this inside performHybridSearch)
    const isHybrid = this.localDataValue.length > 0;
    if (!isHybrid && query.length < this.minLengthValue) {
      // Too short for remote; close the dropdown (or reset when alwaysShow is true)
      this.isLoading = false;
      this.close();
      return;
    }

    // Show loading state for remote searches only if not already loading
    if (!this.isLoading) {
      this.showLoading();
    }

    // Debounce only remote searches
    this.searchTimeout = setTimeout(() => {
      // Check if the input value has changed since this timeout was scheduled
      const currentQuery = this.inputTarget.value.trim();
      if (currentQuery !== query) {
        // Input has changed, don't execute this outdated search
        // The new input value should have already triggered its own handler
        return;
      }

      if (this.localDataValue.length > 0) {
        // Hybrid search: perform both local and remote searches
        this.performHybridSearch(query);
      } else {
        // Pure remote search
        this.fetchSuggestions(query);
      }
    }, this.delayValue);
  }

  handleKeydown(event) {
    if (!this.isOpen) {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        const query = this.inputTarget.value.trim();
        const hasLocal = this.localDataValue.length > 0;
        const remoteRequiresMore =
          this.urlValue && !hasLocal && this.minLengthValue > 0 && query.length < this.minLengthValue;
        if (remoteRequiresMore) return;

        // Open the dropdown (and fetch if needed) but do not pre-select
        event.preventDefault();
        this.keyboardNavigating = true; // prevent any autoSelectFirst behavior
        this.updateKeyboardNavigationClass();
        this.handleInput({ target: this.inputTarget });
        return;
      } else if (event.key !== "Escape") {
        return;
      }
    }

    // If the results container is focused and navigation keys are pressed,
    // ensure the input gets focus first for consistent behavior
    if (event.target === this.resultsTarget && ["ArrowDown", "ArrowUp", "Enter"].includes(event.key)) {
      this.inputTarget.focus();
    }

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this.keyboardNavigating = true;
        this.updateKeyboardNavigationClass();
        this.navigateDown();
        break;
      case "ArrowUp":
        event.preventDefault();
        this.keyboardNavigating = true;
        this.updateKeyboardNavigationClass();
        this.navigateUp();
        break;
      case "Enter":
        event.preventDefault();
        this.selectCurrent();
        break;
      case "Escape":
        if (!this.bubbleEscapeValue) {
          event.preventDefault();
        }
        if (this.clearOnEscapeValue && this.inputTarget.value) {
          this.clearInput();
        } else {
          this.close();
        }
        break;
      case "Tab":
        if (!this.alwaysShowValue) {
          this.close();
        }
        break;
    }
  }

  async fetchSuggestions(query) {
    // Cancel previous request
    if (this.abortController) this.abortController.abort();
    this.abortController = new AbortController();

    try {
      const url = new URL(this.urlValue, window.location.origin);
      url.searchParams.set("q", query);

      const response = await fetch(url, {
        signal: this.abortController.signal,
        headers: {
          Accept: "application/json",
        },
      });

      if (!response.ok) throw new Error("Network response was not ok");

      const data = await response.json();
      this.displaySuggestions(data.suggestions || data, query);
    } catch (error) {
      if (error.name !== "AbortError") {
        console.error("Autocomplete fetch error:", error);
        this.showError();
      }
    }
  }

  async performHybridSearch(query) {
    // Get local results immediately
    const localResults = this.getLocalResults(query);

    // Check if query meets minimum length requirement for remote search
    const shouldFetchRemote = query.length >= this.minLengthValue;

    if (!shouldFetchRemote) {
      // Only show local results if query is too short for remote search
      this.displaySuggestions(localResults, query);
      return;
    }
    // For hybrid searches, don't show local results immediately - wait for remote
    // This keeps the loading state visible until we have all results

    // Cancel previous request
    if (this.abortController) this.abortController.abort();
    this.abortController = new AbortController();

    try {
      const url = new URL(this.urlValue, window.location.origin);
      url.searchParams.set("q", query);

      const response = await fetch(url, {
        signal: this.abortController.signal,
        headers: {
          Accept: "application/json",
        },
      });

      if (!response.ok) throw new Error("Network response was not ok");

      const data = await response.json();
      const remoteResults = data.suggestions || data;

      // Combine results: local first, then remote
      this.displayHybridSuggestions(localResults, remoteResults, query);
    } catch (error) {
      if (error.name !== "AbortError") {
        console.error("Autocomplete fetch error:", error);
        // Show local results even if remote fails
        this.displaySuggestions(localResults, query);
      }
    }
  }

  getLocalResults(query) {
    const filtered = this.localDataValue.filter((item) => {
      // Handle simple strings
      if (typeof item === "string") {
        return this.matchesQuery(item, query);
      }

      // Handle objects with search keys
      return this.searchKeysValue.some((key) => {
        const value = item[key];
        return value && this.matchesQuery(value.toString(), query);
      });
    });

    const sorted = this.sortSuggestionsByPrefixPriority(filtered, query);
    return sorted.slice(0, this.maxSuggestionsValue);
  }

  searchLocalData(query) {
    // Reuse getLocalResults to avoid duplicated filtering logic
    const suggestions = this.getLocalResults(query);
    this.displaySuggestions(suggestions, query);
  }

  displaySuggestions(suggestions, query) {
    // Track the last search query
    this.lastSearchQuery = query;

    if (!suggestions || suggestions.length === 0) {
      this.showNoResults();
      return;
    }

    this.isLoading = false; // End loading state
    const sorted = this.sortSuggestionsByPrefixPriority(suggestions, query);
    const html = this.renderSuggestions(sorted, query, 0);
    this.resultsTarget.innerHTML = html;
    this.open();

    // Auto-select first suggestion if enabled, not currently keyboard navigating, and user is actively searching
    if (this.autoSelectFirstValue && suggestions.length > 0 && !this.keyboardNavigating && query && query.length > 0) {
      this.selectedIndex = 0;
      this.updateSelection();
    }
  }

  displayHybridSuggestions(localResults, remoteResults, query) {
    // Track the last search query
    this.lastSearchQuery = query;

    if ((!localResults || localResults.length === 0) && (!remoteResults || remoteResults.length === 0)) {
      this.showNoResults();
      return;
    }

    this.isLoading = false; // End loading state
    let html = "";
    let indexOffset = 0;

    // Add local results first
    if (localResults && localResults.length > 0) {
      const sortedLocal = this.sortSuggestionsByPrefixPriority(localResults, query);
      html += this.renderSuggestions(sortedLocal, query, indexOffset);
      indexOffset += sortedLocal.length;
    }

    // Add separator if we have both local and remote results
    if (localResults && localResults.length > 0 && remoteResults && remoteResults.length > 0) {
      html += this.renderSeparator();
    }

    // Add remote results
    if (remoteResults && remoteResults.length > 0) {
      const sortedRemote = this.sortSuggestionsByPrefixPriority(remoteResults, query);
      html += this.renderSuggestions(sortedRemote, query, indexOffset);
    }

    this.resultsTarget.innerHTML = html;
    this.open();

    // Auto-select first suggestion if enabled, we have any results, not currently keyboard navigating, and user is actively searching
    const totalResults = (localResults?.length || 0) + (remoteResults?.length || 0);
    if (this.autoSelectFirstValue && totalResults > 0 && !this.keyboardNavigating && query && query.length > 0) {
      this.selectedIndex = 0;
      this.updateSelection();
    }
  }

  renderSuggestions(suggestions, query, startIndex = 0) {
    return suggestions
      .map((suggestion, index) => {
        const actualIndex = startIndex + index;
        const text =
          typeof suggestion === "string" ? suggestion : suggestion.title || suggestion.name || suggestion.label;
        const subtitle = suggestion.subtitle || suggestion.email || suggestion.description;

        const displayText = this.highlightMatchesValue ? this.highlightText(text, query) : text;
        const displaySubtitle = subtitle && this.highlightMatchesValue ? this.highlightText(subtitle, query) : subtitle;
        const icon = suggestion.icon || "item";
        const customIconHtml = suggestion.customIcon;
        const badge = suggestion.badge;

        const iconSvg = customIconHtml || this.getIconSvg(icon);

        // Ensure we have a proper object for JSON serialization
        const dataForJson = typeof suggestion === "string" ? { title: suggestion } : suggestion;

        // Properly encode JSON for HTML attribute
        const jsonData = JSON.stringify(dataForJson).replace(/"/g, "&quot;");

        const extraSuggestionClasses =
          this.hasSuggestionClassValue && this.suggestionClassValue ? ` ${this.suggestionClassValue}` : "";
        return `
        <button type="button"
                class="outline-none w-full text-left px-4 py-3 flex items-center gap-3 group${extraSuggestionClasses}"
                data-autocomplete-target="suggestion"
                data-action="click->autocomplete#selectSuggestion mousedown->autocomplete#applySelectionStyling mousemove->autocomplete#handleMouseMove"
                data-value="${this.escapeHtml(text)}"
                data-suggestion-data="${jsonData}"
                data-index="${actualIndex}"
                role="option"
                tabindex="-1"
                ${actualIndex === this.selectedIndex ? 'aria-selected="true"' : ""}>
          ${iconSvg}
          <div class="flex-grow">
            <div class="flex items-center gap-2 justify-between">
              <span class="text-sm text-neutral-700 dark:text-neutral-300">${displayText}</span>
              ${badge ? `<span class="inline-flex">${badge}</span>` : ""}
            </div>
            ${
              displaySubtitle
                ? `<div class="text-xs text-neutral-500 dark:text-neutral-400">${displaySubtitle}</div>`
                : ""
            }
          </div>
        </button>
      `;
      })
      .join("");
  }

  renderSeparator() {
    return `
      <div class="px-4 pt-3 pb-1.5 border-t border-neutral-200 dark:border-neutral-700">
        <div class="text-xs font-medium text-neutral-500 dark:text-neutral-400 uppercase tracking-wide">
          ${this.separatorTextValue}
        </div>
      </div>
    `;
  }

  showLoading() {
    this.isLoading = true;
    this.resultsTarget.innerHTML = `
      <div class="px-4 py-8 text-center">
        <div class="inline-flex items-center gap-2 text-sm text-neutral-500 dark:text-neutral-400">
          <svg class="animate-spin size-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          ${this.loadingTextValue}
        </div>
      </div>
    `;
    this.open();
  }

  showNoResults() {
    this.isLoading = false; // End loading state

    // If noResultsText is empty, close the results container instead of showing "no results" message
    if (!this.noResultsTextValue || this.noResultsTextValue.trim() === "") {
      this.close();
      return;
    }

    this.resultsTarget.innerHTML = `
      <div class="px-4 py-8 text-center text-sm text-neutral-500 dark:text-neutral-400">
        ${this.noResultsTextValue}
      </div>
    `;
    this.open();
  }

  showError() {
    this.isLoading = false; // End loading state
    this.resultsTarget.innerHTML = `
      <div class="px-4 py-8 text-center text-sm text-red-500 dark:text-red-400">
        An error occurred. Please try again.
      </div>
    `;
    this.open();
  }

  highlightText(text, query) {
    // Regular highlighting for exact matches
    const regex = new RegExp(`(${this.escapeRegex(query)})`, "gi");
    return text.replace(regex, '<mark class="bg-yellow-200 dark:bg-yellow-400 font-medium">$1</mark>');
  }

  navigateDown() {
    const suggestions = this.suggestionTargets;
    if (suggestions.length === 0) return;

    // Wrap to the first item when moving down from the last item
    if (this.selectedIndex >= suggestions.length - 1) {
      this.selectedIndex = 0;
    } else {
      this.selectedIndex = this.selectedIndex + 1;
    }
    this.updateSelection();
  }

  navigateUp() {
    const suggestions = this.suggestionTargets;
    if (suggestions.length === 0) return;

    // If nothing is selected or we're at the first item, wrap to the last item
    if (this.selectedIndex <= 0) {
      this.selectedIndex = suggestions.length - 1;
    } else {
      this.selectedIndex = this.selectedIndex - 1;
    }
    this.updateSelection();
  }

  updateSelection() {
    // Get selected classes, with defaults if not specified
    const selectedClasses =
      this.hasSelectedClassValue && this.selectedClassValue
        ? this.selectedClassValue.split(" ").filter((cls) => cls.trim())
        : ["bg-neutral-50", "dark:bg-neutral-800", "selected"];

    this.suggestionTargets.forEach((suggestion, index) => {
      const trailingArrow = suggestion.querySelector("svg.arrow");
      if (index === this.selectedIndex) {
        suggestion.classList.add(...selectedClasses);
        suggestion.setAttribute("aria-selected", "true");
        if (trailingArrow) {
          trailingArrow.classList.add("opacity-100");
        }
        // Only scroll when navigating with keyboard, not when hovering with mouse
        if (this.keyboardNavigating) {
          this.scrollToSuggestion(suggestion);
        }
      } else {
        suggestion.classList.remove(...selectedClasses);
        suggestion.setAttribute("aria-selected", "false");
        if (trailingArrow) {
          trailingArrow.classList.remove("opacity-100");
        }
      }
    });

    // Update input with selected value if autoFill is enabled
    if (this.autoFillValue && this.selectedIndex >= 0) {
      const selectedSuggestion = this.suggestionTargets[this.selectedIndex];
      this.inputTarget.value = selectedSuggestion.dataset.value;
      this.updateClearButtonVisibility();
    }
  }

  scrollToSuggestion(suggestionEl) {
    const container = this.resultsTarget;
    if (!container) return;

    const containerRect = container.getBoundingClientRect();
    const suggestionRect = suggestionEl.getBoundingClientRect();

    // Calculate the suggestion's position relative to the scrollable container
    // Use getBoundingClientRect to get accurate positions relative to viewport
    const suggestionRelativeTop = suggestionRect.top - containerRect.top;
    const suggestionRelativeBottom = suggestionRelativeTop + suggestionRect.height;
    const containerScrollTop = container.scrollTop;
    const containerHeight = containerRect.height;

    // Define padding: scroll when the suggestion is within this distance from the edge
    const scrollPadding = suggestionRect.height * 1;

    // Check if we need to scroll down
    if (suggestionRelativeBottom > containerHeight - scrollPadding) {
      // Scroll so the suggestion is visible with padding below
      container.scrollTop = containerScrollTop + (suggestionRelativeBottom - containerHeight + scrollPadding);
    }
    // Check if we need to scroll up
    else if (suggestionRelativeTop < scrollPadding) {
      // Scroll so the suggestion is visible with padding above
      container.scrollTop = containerScrollTop + (suggestionRelativeTop - scrollPadding);
    }
  }

  selectCurrent() {
    if (this.selectedIndex >= 0 && this.suggestionTargets[this.selectedIndex]) {
      this.selectSuggestion({ currentTarget: this.suggestionTargets[this.selectedIndex] });
    } else if (this.inputTarget.value.trim()) {
      // If freeSolo is enabled, allow submitting arbitrary values
      if (this.freeSoloValue) {
        this.lastSelectedValue = this.inputTarget.value.trim(); // Track the arbitrary value
        this.submitSearch(this.inputTarget.value.trim());
      } else {
        // When freeSolo is disabled, only submit if the input matches a valid option
        if (this.isValidOption(this.inputTarget.value.trim())) {
          this.submitSearch(this.inputTarget.value.trim());
        }
        // If no valid option and freeSolo is disabled, do nothing (prevent submission)
      }
    }
  }

  selectSuggestion(event) {
    const value = event.currentTarget.dataset.value;

    let suggestionData = {};
    try {
      const dataString = event.currentTarget.dataset.suggestionData;
      if (dataString && dataString.trim() !== "") {
        // Decode HTML entities back to quotes
        const decodedData = dataString.replace(/&quot;/g, '"');
        suggestionData = JSON.parse(decodedData);
      }
    } catch (error) {
      console.warn("Failed to parse suggestion data:", error);
      suggestionData = { title: value };
    }

    // Update input based on URL presence and preserveSearchOnSelect setting
    const hasUrl = suggestionData.url || suggestionData.route || suggestionData.href;
    const shouldUpdateInput = !hasUrl || (hasUrl && !this.preserveSearchOnSelectValue);
    if (shouldUpdateInput) {
      this.inputTarget.value = value;
      this.lastSelectedValue = value; // Track the selected value for freeSolo behavior
      this.updateClearButtonVisibility();
    }

    // Determine if we should close - respect preserveSearchOnSelect for URL items
    const shouldClose = this.closeOnSelectValue && !(hasUrl && this.preserveSearchOnSelectValue);
    if (shouldClose) this.close();

    // Execute configured action if specified
    this.executeConfiguredAction(suggestionData);

    // Navigate to URL if present (automatic behavior)
    this.navigateToUrl(suggestionData);

    // Dispatch custom event with full data
    this.dispatch("select", {
      detail: {
        value,
        data: suggestionData,
      },
    });

    // Submit if enabled
    if (this.submitOnSelectValue) {
      this.submitSearch(value);
    }
  }

  applySelectionStyling(event) {
    // Apply visual styling immediately on mousedown for better UX
    const clickedSuggestion = event.currentTarget;
    const index = parseInt(clickedSuggestion.dataset.index);

    if (!isNaN(index)) {
      // Update the selected index
      this.selectedIndex = index;
      // Apply the visual styling immediately
      this.updateSelection();
    }
  }

  submitSearch(value) {
    // Find the parent form and submit it
    const form = this.inputTarget.closest("form");
    if (form) {
      // Dispatch custom event before submitting
      this.dispatch("submit", { detail: { value } });
      form.submit();
    }
  }

  navigateToUrl(suggestionData) {
    // Check if the selected item has a URL/route to navigate to
    const targetUrl = suggestionData.url || suggestionData.route || suggestionData.href;

    if (targetUrl) {
      // Navigate to the actual URL/route
      if (targetUrl.startsWith("http") || targetUrl.startsWith("//")) {
        // External URL - open in same window
        window.location.href = targetUrl;
      } else {
        // Internal route - use Turbo if available, otherwise regular navigation
        if (window.Turbo && window.Turbo.visit) {
          window.Turbo.visit(targetUrl);
        } else {
          window.location.href = targetUrl;
        }
      }
    }
    // If no URL is provided, do nothing - just stay in the current state
  }

  clearInput() {
    this.inputTarget.value = "";
    this.close();
    this.updateClearButtonVisibility();
    this.inputTarget.focus();

    // Clear last query and selected value
    this.lastSearchQuery = null;
    this.lastSelectedValue = null;
  }

  updateClearButtonVisibility() {
    if (this.hasClearButtonTarget) {
      if (this.inputTarget.value) {
        this.clearButtonTarget.classList.remove("hidden");
        this.clearButtonTarget.classList.add("flex");
      } else {
        this.clearButtonTarget.classList.add("hidden");
        this.clearButtonTarget.classList.remove("flex");
      }
    }
  }

  handleFormSubmit(event) {
    // Only validate if freeSolo is disabled and this input has a value
    if (!this.freeSoloValue && this.inputTarget.value.trim() && !this.isValidOption(this.inputTarget.value.trim())) {
      event.preventDefault();
      return false;
    }
  }

  isValidOption(value) {
    // Check if the value matches any local data exactly
    if (this.localDataValue.length > 0) {
      return this.localDataValue.some((item) => {
        const itemValue = typeof item === "string" ? item : item.title || item.name || item.label;
        return itemValue && itemValue.toLowerCase() === value.toLowerCase();
      });
    }

    // For remote data, allow submission (can't validate without request)
    return this.urlValue ? true : false;
  }

  async open() {
    if (!this.isOpen) {
      this.isOpen = true;
      this.selectedIndex = -1;

      if (this.renderModeValue === "popover") {
        if (!this.alwaysShowValue) {
          this.resultsTarget.classList.remove("hidden");
          this.resultsTarget.classList.add("block");
        }

        // Position instantly with Floating UI (no animation for positioning)
        await this.positionResults();

        // Add animation classes only for opacity (not positioning)
        requestAnimationFrame(() => {
          this.resultsTarget.classList.add("opacity-100");
          this.resultsTarget.classList.remove("opacity-0");
        });
      } else {
        // Inline mode: ensure container is visible; do not set positioning
        if (!this.alwaysShowValue) {
          this.resultsTarget.classList.remove("hidden", "opacity-0");
        }
      }
    }
  }

  async positionResults() {
    if (this.renderModeValue === "inline") return; // No floating/positioning in inline mode
    if (this.cleanupAutoUpdate) this.cleanupAutoUpdate();

    const referenceEl = this.anchorValue === "form" ? this.element : this.inputTarget;

    this.cleanupAutoUpdate = autoUpdate(referenceEl, this.resultsTarget, async () => {
      const { x, y, placement } = await computePosition(referenceEl, this.resultsTarget, {
        placement: this.placementValue,
        middleware: [
          offset(this.offsetDistanceValue),
          flip({
            fallbackPlacements: ["bottom-start", "top-start", "bottom-end", "top-end"],
          }),
          shift({ padding: 8 }),
        ],
      });

      Object.assign(this.resultsTarget.style, {
        left: `${x}px`,
        top: `${y}px`,
        position: "absolute",
      });

      // Update classes based on placement for better styling
      this.resultsTarget.classList.toggle("placement-top", placement.startsWith("top"));
      this.resultsTarget.classList.toggle("placement-bottom", placement.startsWith("bottom"));
    });
  }

  close() {
    if (!this.isOpen) return;

    // Reset loading state when closing
    this.isLoading = false;

    // Reset selection so next open starts fresh
    this.selectedIndex = -1;

    // If alwaysShow is enabled, don't actually close - just reset to initial state
    if (this.alwaysShowValue) {
      // Reset to initial search state instead of closing
      if (this.urlValue && this.localDataValue.length > 0) {
        // For hybrid search with empty query, only show local results (respects min-length for remote)
        this.performHybridSearch("");
      } else if (this.urlValue) {
        // Only fetch remote if min-length allows empty queries
        if ("".length >= this.minLengthValue) {
          this.fetchSuggestions("");
        }
      } else {
        this.searchLocalData("");
      }
      return;
    }

    if (this.renderModeValue === "popover") {
      // Clean up positioning
      if (this.cleanupAutoUpdate) {
        this.cleanupAutoUpdate();
        this.cleanupAutoUpdate = null;
      }

      // Remove animation classes (only opacity, not positioning)
      this.resultsTarget.classList.remove("opacity-100");
      this.resultsTarget.classList.add("opacity-0");

      // Hide after animation
      setTimeout(() => {
        this.resultsTarget.classList.add("hidden");
        this.resultsTarget.classList.remove("block");
        this.isOpen = false;

        // Reset positioning styles
        this.resultsTarget.style.left = "";
        this.resultsTarget.style.top = "";
        this.resultsTarget.style.position = "";
        this.resultsTarget.style.width = "";
      }, 150);
    } else {
      // Inline mode: clear content and hide container
      this.resultsTarget.innerHTML = "";
      this.resultsTarget.classList.add("hidden");
      this.isOpen = false;
    }
  }

  getIconSvg(icon) {
    const iconMap = {
      folder:
        '<svg xmlns="http://www.w3.org/2000/svg" class="size-4 shrink-0" width="18" height="18" viewBox="0 0 18 18"><g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" stroke="currentColor"><path d="M2.25,8.75V4.75c0-1.105,.895-2,2-2h1.951c.607,0,1.18,.275,1.56,.748l.603,.752h5.386c1.105,0,2,.895,2,2v2.844"></path><path d="M4.25,6.75H13.75c1.105,0,2,.895,2,2v4.5c0,1.105-.895,2-2,2H4.25c-1.105,0-2-.895-2-2v-4.5c0-1.105,.895-2,2-2Z"></path></g></svg>',
      file: '<svg xmlns="http://www.w3.org/2000/svg" class="size-4 shrink-0" width="18" height="18" viewBox="0 0 18 18"><g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" stroke="currentColor"><line x1="5.75" y1="6.75" x2="7.75" y2="6.75"></line><line x1="5.75" y1="9.75" x2="12.25" y2="9.75"></line><line x1="5.75" y1="12.75" x2="12.25" y2="12.75"></line><path d="M2.75,14.25V3.75c0-1.105,.895-2,2-2h5.586c.265,0,.52,.105,.707,.293l3.914,3.914c.188,.188,.293,.442,.293,.707v7.586c0,1.105-.895,2-2,2H4.75c-1.105,0-2-.895-2-2Z"></path><path d="M15.16,6.25h-3.41c-.552,0-1-.448-1-1V1.852"></path></g></svg>',
      search:
        '<svg xmlns="http://www.w3.org/2000/svg" class="size-4 shrink-0" width="18" height="18" viewBox="0 0 18 18"><g fill="currentColor"><path d="M15.25,16c-.192,0-.384-.073-.53-.22l-3.965-3.965c-.293-.293-.293-.768,0-1.061s.768-.293,1.061,0l3.965,3.965c.293,.293,.293,.768,0,1.061-.146,.146-.338,.22-.53,.22Z"></path><path d="M7.75,13.5c-3.17,0-5.75-2.58-5.75-5.75S4.58,2,7.75,2s5.75,2.58,5.75,5.75-2.58,5.75-5.75,5.75Zm0-10c-2.343,0-4.25,1.907-4.25,4.25s1.907,4.25,4.25,4.25,4.25-1.907,4.25-4.25-1.907-4.25-4.25-4.25Z"></path></g></svg>',
      recent:
        '<svg xmlns="http://www.w3.org/2000/svg" class="size-4 shrink-0" width="18" height="18" viewBox="0 0 18 18"><g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" stroke="currentColor"><circle cx="9" cy="9" r="7.25"></circle><polyline points="9 5.5 9 9 11.5 11.5"></polyline></g></svg>',
      item: "", // If no icon is provided, the default is an empty string
    };

    return iconMap[icon] || iconMap["item"];
  }

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  escapeRegex(string) {
    return string.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  matchesQuery(text, query, strategy = this.matchStrategyValue) {
    if (!query || query.trim() === "") return true;

    const lowerText = text.toLowerCase();
    const lowerQuery = query.toLowerCase().trim();

    switch (strategy) {
      case "prefix":
        return lowerText.startsWith(lowerQuery);
      case "exact":
        return lowerText === lowerQuery;
      case "contains":
      default:
        return lowerText.includes(lowerQuery);
    }
  }

  // Determine priority for sorting: exact prefix > prefix > contains > none
  computeMatchPriorityForText(text, query) {
    if (!query || query.trim() === "") return 3;
    const lowerText = (text || "").toLowerCase();
    const lowerQuery = query.toLowerCase().trim();
    if (lowerText === lowerQuery) return 0;
    if (lowerText.startsWith(lowerQuery)) return 1;
    if (lowerText.includes(lowerQuery)) return 2;
    return 3;
  }

  // Returns best priority across the suggestion's searchable fields
  computeSuggestionPriority(suggestion, query) {
    if (!query || query.trim() === "") return 3;
    if (typeof suggestion === "string") {
      return this.computeMatchPriorityForText(suggestion, query);
    }
    let best = 3;
    for (const key of this.searchKeysValue) {
      const value = suggestion && suggestion[key];
      if (!value) continue;
      const priority = this.computeMatchPriorityForText(String(value), query);
      if (priority < best) best = priority;
      if (best === 0) break; // can't get better than exact
    }
    return best;
  }

  // Stable sort by prefix priority while preserving original order for ties
  sortSuggestionsByPrefixPriority(suggestions, query) {
    if (!Array.isArray(suggestions) || !query || query.trim() === "") return suggestions;
    return suggestions
      .map((item, index) => ({ item, index, priority: this.computeSuggestionPriority(item, query) }))
      .sort((a, b) => {
        if (a.priority !== b.priority) return a.priority - b.priority;
        return a.index - b.index;
      })
      .map((x) => x.item);
  }

  executeConfiguredAction(suggestionData) {
    if (!this.selectActionValue) return;

    // Check if the suggestion has its own action override
    const actionToExecute = suggestionData.action || this.selectActionValue;

    try {
      // Parse the action string (e.g., "modal#close:prevent")
      const [controllerAction, ...modifiers] = actionToExecute.split(":");
      const [controllerName, actionName] = controllerAction.split("#");

      if (!controllerName || !actionName) {
        console.warn('Invalid action format. Expected format: "controller#action" or "controller#action:modifier"');
        return;
      }

      // Find the target controller
      let targetController = this.application.getControllerForElementAndIdentifier(this.element, controllerName);

      if (!targetController) {
        // Look for controller in parent elements
        let currentElement = this.element.parentElement;

        while (currentElement && !targetController) {
          targetController = this.application.getControllerForElementAndIdentifier(currentElement, controllerName);
          currentElement = currentElement.parentElement;
        }

        if (!targetController) {
          console.warn(`Controller "${controllerName}" not found for action "${actionToExecute}"`);
          return;
        }
      }

      // Execute the action
      if (typeof targetController[actionName] === "function") {
        // Create a fake event object that includes our suggestion data
        const fakeEvent = {
          preventDefault: () => {},
          stopPropagation: () => {},
          detail: { suggestionData },
          type: "autocomplete:select",
        };

        // Check for prevent modifier
        if (modifiers.includes("prevent")) {
          fakeEvent.preventDefault();
        }

        targetController[actionName](fakeEvent);
      } else {
        console.warn(`Action "${actionName}" not found on controller "${controllerName}"`);
      }
    } catch (error) {
      console.error("Error executing configured action:", error);
    }
  }

  updateKeyboardNavigationClass() {
    if (this.hasResultsTarget && this.resultsTarget) {
      if (this.keyboardNavigating) {
        this.resultsTarget.classList.add("keyboard-navigating");
      } else {
        this.resultsTarget.classList.remove("keyboard-navigating");
      }
    }
  }

  clearHoverStates() {
    // Remove hover states from all suggestions when keyboard navigating
    // and mouse leaves the results area, but preserve selected state
    this.suggestionTargets.forEach((suggestion, index) => {
      // Don't touch the selected item's styling
      if (index === this.selectedIndex) return;

      // Clear arrow opacity for non-selected items only
      const trailingArrow = suggestion.querySelector("svg.arrow");
      if (trailingArrow) {
        trailingArrow.classList.remove("opacity-100");
      }
    });
  }

  handleMouseMove(event) {
    // Ignore mousemove events where the mouse didn't actually move.
    // This happens when content scrolls under a stationary cursor (e.g., during keyboard navigation).
    // The browser fires mousemove events on elements that pass under the cursor, but movementX/Y will be 0.
    if (event.movementX === 0 && event.movementY === 0) {
      return;
    }

    // Reset keyboard navigation when mouse is used
    this.keyboardNavigating = false;
    this.updateKeyboardNavigationClass();

    // Update selected index based on mouse position
    const suggestionElement = event.currentTarget;
    const index = parseInt(suggestionElement.dataset.index);
    if (!isNaN(index)) {
      this.selectedIndex = index;
      this.updateSelection();
    }
  }
}

// Base class for autocomplete extension controllers
export class BaseAutocompleteExtension extends Controller {
  connect() {
    // Find the main autocomplete controller
    // Wait a tick to ensure all controllers are connected
    setTimeout(() => {
      this.autocompleteController = this.findAutocompleteController();

      if (!this.autocompleteController) {
        console.warn(`${this.constructor.name} requires an autocomplete controller on the same element`);
        return;
      }

      this.originalMethods = new Map();
      this.initialize();
    }, 100);
  }

  disconnect() {
    this.restoreOriginalMethods();
  }

  // Override this method in subclasses
  initialize() {
    // Subclasses should implement their initialization logic here
  }

  findAutocompleteController() {
    const controllers = this.application.controllers.filter(
      (controller) => controller.element === this.element && controller.identifier === "autocomplete",
    );
    return controllers[0];
  }

  // Helper method to override methods safely
  overrideMethod(methodName, newMethod) {
    if (this.autocompleteController[methodName]) {
      // Store original method
      this.originalMethods.set(methodName, this.autocompleteController[methodName].bind(this.autocompleteController));
      // Override with new method
      this.autocompleteController[methodName] = newMethod.bind(this);
    }
  }

  // Helper method to call original method
  callOriginal(methodName, ...args) {
    const originalMethod = this.originalMethods.get(methodName);
    if (originalMethod) {
      return originalMethod(...args);
    }
  }

  // Restore all overridden methods
  restoreOriginalMethods() {
    if (!this.autocompleteController) return;

    this.originalMethods.forEach((originalMethod, methodName) => {
      this.autocompleteController[methodName] = originalMethod;
    });
    this.originalMethods.clear();
  }

  // Shared suggestion rendering with customizable options
  renderSuggestion(suggestion, query, index, options = {}) {
    const {
      startIndex = 0,
      showParentIndicator = false,
      showRemoveButton = false,
      customClasses = "",
      customIcon = null,
    } = options;

    const actualIndex = startIndex + index;
    const text = typeof suggestion === "string" ? suggestion : suggestion.title || suggestion.name || suggestion.label;
    const subtitle = suggestion.subtitle || suggestion.email || suggestion.description;
    const isParent = suggestion.children !== undefined;
    const isRecent = suggestion.isRecent || false;

    const displayText = this.autocompleteController.highlightMatchesValue
      ? this.autocompleteController.highlightText(text, query)
      : text;
    const displaySubtitle =
      subtitle && this.autocompleteController.highlightMatchesValue
        ? this.autocompleteController.highlightText(subtitle, query)
        : subtitle;

    // Determine icon
    let icon;
    if (customIcon) {
      icon = customIcon;
    } else if (suggestion.icon) {
      icon = suggestion.icon;
    } else if (isParent) {
      icon = "folder";
    } else if (isRecent) {
      icon = "recent";
    } else {
      icon = "item";
    }

    const customIconHtml = suggestion.customIcon;
    const badge = suggestion.badge;
    const iconSvg = customIconHtml || this.autocompleteController.getIconSvg(icon);

    // Ensure we have a proper object for JSON serialization
    const dataForJson = typeof suggestion === "string" ? { title: suggestion } : suggestion;
    const jsonData = JSON.stringify(dataForJson).replace(/"/g, "&quot;");

    const extraSuggestionClasses =
      this.autocompleteController.hasSuggestionClassValue && this.autocompleteController.suggestionClassValue
        ? ` ${this.autocompleteController.suggestionClassValue}`
        : "";

    const parentAttributes = showParentIndicator && isParent ? `data-is-parent="true"` : "";
    const removeButtonSpace = showRemoveButton && isRecent ? "pr-12" : "";

    const removeButton =
      showRemoveButton && isRecent
        ? `
      <button type="button"
              class="absolute right-2.5 top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-100 p-1 hover:bg-neutral-200 text-neutral-400 hover:text-neutral-500 dark:text-neutral-500 dark:hover:bg-neutral-700 dark:hover:text-neutral-300 rounded-full"
              data-action="click->autocomplete-recent-searches#removeRecentSearch"
              data-search="${this.autocompleteController.escapeHtml(text)}"
              onclick="event.stopPropagation()"
              tabindex="-1">
        <svg xmlns="http://www.w3.org/2000/svg" class="size-3.5" width="12" height="12" viewBox="0 0 12 12">
          <g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" stroke="currentColor">
            <line x1="9" y1="3" x2="3" y2="9"></line>
            <line x1="3" y1="3" x2="9" y2="9"></line>
          </g>
        </svg>
      </button>
    `
        : "";

    return `
      <div class="relative group">
        <button type="button"
                class="outline-none w-full text-left px-4 py-3 flex items-center gap-3 ${removeButtonSpace} group${extraSuggestionClasses}${customClasses}"
                data-autocomplete-target="suggestion"
                data-action="click->autocomplete#selectSuggestion mousedown->autocomplete#applySelectionStyling mousemove->autocomplete#handleMouseMove"
                data-value="${this.autocompleteController.escapeHtml(text)}"
                data-suggestion-data="${jsonData}"
                data-index="${actualIndex}"
                ${parentAttributes}
                role="option"
                tabindex="-1"
                ${actualIndex === this.autocompleteController.selectedIndex ? 'aria-selected="true"' : ""}>
          ${iconSvg}
          <div class="flex-grow">
            <div class="flex items-center gap-2 justify-between">
              <span class="text-sm text-neutral-700 dark:text-neutral-300">${displayText}</span>
              ${badge ? `<span class="inline-flex">${badge}</span>` : ""}
            </div>
            ${
              displaySubtitle
                ? `<div class="text-xs text-neutral-500 dark:text-neutral-400">${displaySubtitle}</div>`
                : ""
            }
          </div>
        </button>
        ${removeButton}
      </div>
    `;
  }

  // Helper method for rendering multiple suggestions
  renderSuggestions(suggestions, query, startIndex = 0, options = {}) {
    return suggestions
      .map((suggestion, index) =>
        this.renderSuggestion(suggestion, query, index, {
          ...options,
          startIndex,
        }),
      )
      .join("");
  }

  // Helper method to manage event listeners
  replaceEventListener(target, eventType, oldHandler, newHandler) {
    if (target && oldHandler) {
      target.removeEventListener(eventType, oldHandler);
    }
    if (target && newHandler) {
      target.addEventListener(eventType, newHandler);
    }
  }
}
