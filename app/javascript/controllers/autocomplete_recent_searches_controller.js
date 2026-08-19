import { BaseAutocompleteExtension } from "controllers/autocomplete_controller";

export default class extends BaseAutocompleteExtension {
  static targets = ["input", "results", "clearButton"];
  static values = {
    // This controller is specifically for recent searches functionality
    // If you don't need recent searches, don't add this controller
    recentStorageKey: { type: String, default: "autocomplete-recent" }, // localStorage key for storing recent searches
    maxRecentItems: { type: Number, default: 5 }, // Maximum number of recent searches to store
    showRecentWhileTyping: { type: Boolean, default: false }, // Keep recent searches visible while typing
    deduplicate: { type: Boolean, default: true }, // Remove duplicates between recent and regular suggestions
    recentMatchStrategy: { type: String, default: "" }, // "prefix", "contains", "exact" - how to match recent searches while typing. "" Empty string uses core matchStrategy. "prefix" will match the beginning of the recent search. "contains" will match any part of the recent search. "exact" will match the exact recent search.
    preserveIcons: { type: Boolean, default: false }, // Whether to preserve original icons in recent searches (true) or always use recent icon (false)
  };

  initialize() {
    // Initialize recent searches
    this.recentSearches = this.loadRecentSearches();

    // Check if autocomplete controller is available before proceeding
    if (!this.autocompleteController) {
      return;
    }

    // Override methods to handle recent searches
    this.overrideMethod("handleInput", this.handleInputWithRecent);
    this.overrideMethod("selectSuggestion", this.selectSuggestionWithRecent);
    this.overrideMethod("submitSearch", this.submitSearchWithRecent);
    this.overrideMethod("displaySuggestions", this.displaySuggestionsWithRecent);
    this.overrideMethod("searchLocalData", this.searchLocalDataWithRecent);
    this.overrideMethod("fetchSuggestions", this.fetchSuggestionsWithRecent);

    // Handle focus event listener replacement
    this.boundHandleInitialFocusWithRecent = this.handleInitialFocusWithRecent.bind(this);
    this.replaceEventListener(
      this.autocompleteController.inputTarget,
      "focus",
      this.autocompleteController.boundHandleInitialFocus,
      this.boundHandleInitialFocusWithRecent,
    );
  }

  disconnect() {
    // Restore focus event listener
    this.replaceEventListener(
      this.autocompleteController?.inputTarget,
      "focus",
      this.boundHandleInitialFocusWithRecent,
      this.autocompleteController?.boundHandleInitialFocus,
    );

    super.disconnect();
  }

  handleInputWithRecent(event) {
    const query = event.target.value.trim();

    this.autocompleteController.updateClearButtonVisibility();

    // Clear last query if current query is different
    if (query !== this.autocompleteController.lastSearchQuery) {
      this.autocompleteController.lastSearchQuery = null;
    }

    // Reset keyboard navigation state when new input triggers search
    this.autocompleteController.keyboardNavigating = false;
    this.autocompleteController.updateKeyboardNavigationClass();

    if (query.length < this.autocompleteController.minLengthValue) {
      if (query.length === 0 && this.recentSearches.length > 0) {
        this.showRecentSearches();
      } else {
        this.autocompleteController.close();
      }
      return;
    }

    // Handle local-only searches immediately (no delay needed)
    if (!this.autocompleteController.urlValue) {
      this.autocompleteController.searchLocalData(query);
      return;
    }

    // Clear existing timeout for remote searches
    if (this.autocompleteController.searchTimeout) clearTimeout(this.autocompleteController.searchTimeout);

    // Show loading state for remote searches only if not already loading
    if (!this.autocompleteController.isLoading) {
      this.autocompleteController.showLoading();
    }

    // Debounce only remote searches
    this.autocompleteController.searchTimeout = setTimeout(() => {
      // Check if the input value has changed since this timeout was scheduled
      const currentQuery = this.autocompleteController.inputTarget.value.trim();
      if (currentQuery !== query) {
        // Input has changed, don't execute this outdated search
        // The new input value should have already triggered its own handler
        return;
      }

      this.autocompleteController.fetchSuggestions(query);
    }, this.autocompleteController.delayValue);
  }

  handleInitialFocusWithRecent() {
    const currentValue = this.autocompleteController.inputTarget.value.trim();

    if (currentValue) {
      // If the query hasn't changed and results container has content, just reopen it
      if (
        currentValue === this.autocompleteController.lastSearchQuery &&
        this.autocompleteController.resultsTarget.innerHTML.trim() !== ""
      ) {
        this.autocompleteController.open();
      } else {
        // Query has changed, trigger new search
        this.handleInputWithRecent({ target: this.autocompleteController.inputTarget });
      }
    } else {
      if (this.autocompleteController.searchOnFocusValue || this.autocompleteController.alwaysShowValue) {
        // If search on focus or always show is enabled, trigger a search with empty query
        // This will now include recent searches merged with regular results
        if (this.autocompleteController.urlValue) {
          this.autocompleteController.fetchSuggestions("");
        } else {
          this.autocompleteController.searchLocalData("");
        }
      } else if (this.recentSearches.length > 0) {
        this.showRecentSearches();
      }
    }
  }

  selectSuggestionWithRecent(event) {
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
    const shouldUpdateInput = !hasUrl || (hasUrl && !this.autocompleteController.preserveSearchOnSelectValue);
    if (shouldUpdateInput) {
      this.autocompleteController.inputTarget.value = value;
      this.autocompleteController.updateClearButtonVisibility();
    }

    // Determine if we should close - respect preserveSearchOnSelect for URL items
    const shouldClose =
      this.autocompleteController.closeOnSelectValue &&
      !(hasUrl && this.autocompleteController.preserveSearchOnSelectValue);
    if (shouldClose) this.autocompleteController.close();

    // Execute configured action if specified
    this.autocompleteController.executeConfiguredAction(suggestionData);

    // Add to recent searches with full suggestion data
    this.addToRecentSearches(suggestionData);

    // Dispatch custom event with full data
    this.autocompleteController.dispatch("select", {
      detail: {
        value,
        data: suggestionData,
      },
    });

    // Submit if enabled
    if (this.autocompleteController.submitOnSelectValue) {
      this.submitSearchWithRecent(value);
    }
  }

  submitSearchWithRecent(value) {
    // Add to recent searches when submitting
    // For manual submissions, create basic suggestion data
    this.addToRecentSearches({ title: value });

    // Call original submit
    this.callOriginal("submitSearch", value);
  }

  showRecentSearches() {
    if (this.recentSearches.length === 0) {
      this.autocompleteController.close();
      return;
    }

    const html = `
      <div class="px-4 pt-3 pb-1.5 text-xs font-medium text-neutral-500 dark:text-neutral-400 uppercase tracking-wider">Recent Searches</div>
      ${this.recentSearches
        .map((search, index) => {
          // Handle both legacy string format and new object format
          const suggestion =
            typeof search === "string" ? { title: search, isRecent: true } : { ...search, isRecent: true };

          // Handle icon based on preserveIcons setting
          const recentSuggestion = { ...suggestion };
          if (!this.preserveIconsValue) {
            recentSuggestion.icon = "recent";
          }

          // Use base class rendering for consistent icon handling
          return this.renderSuggestion(recentSuggestion, "", index, {
            showRemoveButton: true,
          });
        })
        .join("")}
    `;

    this.autocompleteController.resultsTarget.innerHTML = html;
    this.autocompleteController.open();
  }

  removeRecentSearch(event) {
    event.stopPropagation();
    const search = event.currentTarget.dataset.search;
    this.recentSearches = this.recentSearches.filter((s) => {
      const searchText = typeof s === "string" ? s : s.title || s.name || s.label || "";
      return searchText !== search;
    });
    this.saveRecentSearches();

    // Refresh the display
    const currentValue = this.autocompleteController.inputTarget.value.trim();

    if (currentValue === "") {
      // If input is empty, check if we should show merged results or just recent searches
      if (this.autocompleteController.searchOnFocusValue || this.autocompleteController.alwaysShowValue) {
        // Trigger search to show merged results
        if (this.autocompleteController.urlValue) {
          this.autocompleteController.fetchSuggestions("");
        } else {
          this.autocompleteController.searchLocalData("");
        }
      } else {
        // Show just recent searches
        this.showRecentSearches();
      }
    } else {
      // If there's text, trigger a new search to refresh the merged results
      this.handleInputWithRecent({ target: this.autocompleteController.inputTarget });
    }
  }

  addToRecentSearches(suggestionData) {
    // Ensure we have a proper suggestion object
    const suggestion = typeof suggestionData === "string" ? { title: suggestionData } : { ...suggestionData };

    // Add metadata for recent searches and handle icons based on preserveIcons setting
    suggestion.isRecent = true;

    if (!this.preserveIconsValue) {
      // Remove original icon and customIcon to ensure recent icon is always used
      delete suggestion.icon;
      delete suggestion.customIcon;
    }
    // If preserveIcons is true, keep original icon/customIcon data

    // Get the display text for comparison
    const searchText = suggestion.title || suggestion.name || suggestion.label || "";

    // Remove if already exists (compare by text)
    this.recentSearches = this.recentSearches.filter((s) => {
      const existingText = typeof s === "string" ? s : s.title || s.name || s.label || "";
      return existingText !== searchText;
    });

    // Add to beginning
    this.recentSearches.unshift(suggestion);

    // Limit the number of recent searches
    this.recentSearches = this.recentSearches.slice(0, this.maxRecentItemsValue);

    this.saveRecentSearches();
  }

  loadRecentSearches() {
    try {
      const stored = localStorage.getItem(this.recentStorageKeyValue);
      return stored ? JSON.parse(stored) : [];
    } catch {
      return [];
    }
  }

  saveRecentSearches() {
    try {
      localStorage.setItem(this.recentStorageKeyValue, JSON.stringify(this.recentSearches));
    } catch {
      // Ignore localStorage errors
    }
  }

  clearInput() {
    this.autocompleteController.inputTarget.value = "";
    this.autocompleteController.close();
    this.autocompleteController.updateClearButtonVisibility();
    this.autocompleteController.inputTarget.focus();

    // Clear last query
    this.autocompleteController.lastSearchQuery = null;
  }

  // New methods to merge recent searches with regular results

  searchLocalDataWithRecent(query) {
    // Get regular suggestions using core's getLocalResults method
    const regularSuggestions = this.autocompleteController.getLocalResults(query);

    // Merge with recent searches if conditions are met
    const mergedSuggestions = this.getMergedSuggestions(regularSuggestions, query);
    this.autocompleteController.displaySuggestions(mergedSuggestions, query);
  }

  async fetchSuggestionsWithRecent(query) {
    // Cancel previous request
    if (this.autocompleteController.abortController) this.autocompleteController.abortController.abort();
    this.autocompleteController.abortController = new AbortController();

    try {
      const url = new URL(this.autocompleteController.urlValue, window.location.origin);
      url.searchParams.set("q", query);

      const response = await fetch(url, {
        signal: this.autocompleteController.abortController.signal,
        headers: {
          Accept: "application/json",
        },
      });

      if (!response.ok) throw new Error("Network response was not ok");

      const data = await response.json();
      const regularSuggestions = data.suggestions || data;

      // Merge with recent searches if conditions are met
      const mergedSuggestions = this.getMergedSuggestions(regularSuggestions, query);
      this.autocompleteController.displaySuggestions(mergedSuggestions, query);
    } catch (error) {
      if (error.name !== "AbortError") {
        console.error("Autocomplete fetch error:", error);
        this.autocompleteController.showError();
      }
    }
  }

  displaySuggestionsWithRecent(suggestions, query) {
    // Track the last search query
    this.autocompleteController.lastSearchQuery = query;

    if (!suggestions || suggestions.length === 0) {
      this.autocompleteController.showNoResults();
      return;
    }

    const html = this.renderSuggestions(suggestions, query, 0, {
      showRemoveButton: true,
    });

    this.autocompleteController.resultsTarget.innerHTML = html;
    this.autocompleteController.open();

    // Auto-select first suggestion if enabled, not currently keyboard navigating, and user is actively searching
    if (
      this.autocompleteController.autoSelectFirstValue &&
      suggestions.length > 0 &&
      !this.autocompleteController.keyboardNavigating &&
      query &&
      query.length > 0
    ) {
      this.autocompleteController.selectedIndex = 0;
      this.autocompleteController.updateSelection();
    }
  }

  getMergedSuggestions(regularSuggestions, query) {
    // Determine if we should show recent searches
    const shouldShowRecent = this.shouldShowRecentSearches(query);

    if (!shouldShowRecent) {
      return regularSuggestions;
    }

    // Get filtered recent searches based on query and settings
    const filteredRecentSearches = this.getFilteredRecentSearches(query);

    if (filteredRecentSearches.length === 0) {
      return regularSuggestions;
    }

    // Convert recent searches to suggestion format
    const recentSuggestions = filteredRecentSearches.map((search) => {
      // Handle both legacy string format and new object format
      if (typeof search === "string") {
        return {
          title: search,
          icon: "recent",
          isRecent: true,
        };
      } else {
        // Ensure object has isRecent flag and handle icon based on preserveIcons setting
        const recentSuggestion = {
          ...search,
          isRecent: true,
        };

        // Force recent icon only if preserveIcons is disabled
        if (!this.preserveIconsValue) {
          recentSuggestion.icon = "recent";
        }

        return recentSuggestion;
      }
    });

    // Apply deduplication if enabled
    let finalRegularSuggestions = regularSuggestions;
    if (this.deduplicateValue) {
      finalRegularSuggestions = this.deduplicateSuggestions(regularSuggestions, recentSuggestions);
    }

    // Combine recent searches with regular suggestions
    // Put recent searches first, then regular suggestions
    const combined = [...recentSuggestions, ...finalRegularSuggestions];

    // Limit total results to maxSuggestions
    return combined.slice(0, this.autocompleteController.maxSuggestionsValue);
  }

  // Helper method to determine if recent searches should be shown
  shouldShowRecentSearches(query) {
    if (this.recentSearches.length === 0) {
      return false;
    }

    // Always show recent searches if showRecentWhileTyping is enabled
    if (this.showRecentWhileTypingValue) {
      return true;
    }

    // Original behavior: only show recent searches for empty queries when searchOnFocus or alwaysShow is enabled
    return (
      (this.autocompleteController.searchOnFocusValue || this.autocompleteController.alwaysShowValue) &&
      query.length === 0
    );
  }

  // Helper method to filter recent searches based on query and match strategy
  getFilteredRecentSearches(query) {
    if (query.length === 0) {
      // No filtering needed for empty queries
      return this.recentSearches.slice(0, this.maxRecentItemsValue);
    }

    if (!this.showRecentWhileTypingValue) {
      // If showRecentWhileTyping is disabled, don't show any recent searches for non-empty queries
      return [];
    }

    // Determine which matching strategy to use
    const strategy = this.recentMatchStrategyValue || this.autocompleteController.matchStrategyValue;

    // Filter recent searches using the core's matching logic
    const filteredRecents = this.recentSearches.filter((search) => {
      // Get the search text from either string or object format
      const searchText = typeof search === "string" ? search : search.title || search.name || search.label || "";
      return this.autocompleteController.matchesQuery(searchText, query, strategy);
    });

    return filteredRecents.slice(0, this.maxRecentItemsValue);
  }

  // Helper method to deduplicate regular suggestions against recent searches
  deduplicateSuggestions(regularSuggestions, recentSuggestions) {
    if (!regularSuggestions || regularSuggestions.length === 0) {
      return regularSuggestions;
    }

    // Create a set of recent search titles for fast lookup
    const recentTitles = new Set(
      recentSuggestions
        .map((recent) => {
          const title = typeof recent === "string" ? recent : recent.title || recent.name || recent.label;
          return title?.toLowerCase();
        })
        .filter(Boolean),
    );

    // Filter out regular suggestions that match recent searches
    return regularSuggestions.filter((suggestion) => {
      const title =
        typeof suggestion === "string" ? suggestion : suggestion.title || suggestion.name || suggestion.label;
      return title && !recentTitles.has(title.toLowerCase());
    });
  }
}
