import { BaseAutocompleteExtension } from "controllers/autocomplete_controller";

export default class extends BaseAutocompleteExtension {
  static targets = ["breadcrumb"];
  static values = {
    breadcrumb: { type: Boolean, default: false },
  };

  // This controller is specifically for hierarchical navigation
  // If you don't need hierarchical behavior, don't add this controller

  initialize() {
    // Initialize hierarchical state
    this.currentPath = [];
    this.currentPathIcons = []; // Track icons for each level

    // Check if autocomplete controller is available before proceeding
    if (!this.autocompleteController) {
      return;
    }

    this.originalLocalData = [...this.autocompleteController.localDataValue];
    this.originalPlaceholder = this.autocompleteController.inputTarget.placeholder;

    // Override methods for hierarchical navigation
    this.overrideMethod("handleInput", this.handleInputWithHierarchy);
    this.overrideMethod("handleInitialFocus", this.handleInitialFocusWithHierarchy);
    this.overrideMethod("searchLocalData", this.searchLocalDataWithHierarchy);
    this.overrideMethod("selectSuggestion", this.selectSuggestionWithHierarchy);
    this.overrideMethod("displaySuggestions", this.displaySuggestionsWithHierarchy);
    this.overrideMethod("updateClearButtonVisibility", this.updateClearButtonVisibilityWithHierarchy);
    this.overrideMethod("close", this.closeWithHierarchy);

    // Override hybrid search methods if they exist
    if (this.autocompleteController.performHybridSearch) {
      this.overrideMethod("performHybridSearch", this.performHybridSearchWithHierarchy);
    }

    if (this.autocompleteController.displayHybridSuggestions) {
      this.overrideMethod("displayHybridSuggestions", this.displayHybridSuggestionsWithHierarchy);
    }

    if (this.autocompleteController.getLocalResults) {
      this.overrideMethod("getLocalResults", this.getLocalResultsWithHierarchy);
    }

    // Handle input event listener replacement
    // Use the bound handler reference that was stored during setupInputHandlers
    this.boundHandleInputWithHierarchy = this.handleInputWithHierarchy.bind(this);
    this.replaceEventListener(
      this.autocompleteController.inputTarget,
      "input",
      this.autocompleteController.boundHandleInput,
      this.boundHandleInputWithHierarchy,
    );

    // Handle focus event listener replacement
    this.boundHandleInitialFocusWithHierarchy = this.handleInitialFocusWithHierarchy.bind(this);
    this.replaceEventListener(
      this.autocompleteController.inputTarget,
      "focus",
      this.autocompleteController.boundHandleInitialFocus,
      this.boundHandleInitialFocusWithHierarchy,
    );

    // Add our own keydown listener for hierarchical navigation
    this.setupHierarchicalKeydownHandler();

    // Initialize breadcrumb if enabled
    this.updateBreadcrumb();

    // If alwaysShow is enabled, trigger initial search after setup
    if (this.autocompleteController.alwaysShowValue) {
      setTimeout(() => {
        // Always start with local search for initial display in hierarchical mode
        this.searchLocalDataWithHierarchy("");
      }, 50);
    }
  }

  setupHierarchicalKeydownHandler() {
    // Add our own keydown listener that handles backspace specifically
    // This runs before the base controller's handler due to event order
    this.hierarchicalKeydownHandler = (event) => {
      if (
        event.key === "Backspace" &&
        this.autocompleteController.inputTarget.value === "" &&
        this.currentPath.length > 0
      ) {
        event.preventDefault();
        event.stopPropagation();
        this.navigateBack();
        return;
      }
    };

    this.autocompleteController.inputTarget.addEventListener("keydown", this.hierarchicalKeydownHandler, true);
  }

  disconnect() {
    // Remove our hierarchical keydown handler
    if (this.hierarchicalKeydownHandler && this.autocompleteController?.inputTarget) {
      this.autocompleteController.inputTarget.removeEventListener("keydown", this.hierarchicalKeydownHandler, true);
    }

    // Restore input event listener
    this.replaceEventListener(
      this.autocompleteController?.inputTarget,
      "input",
      this.boundHandleInputWithHierarchy,
      this.autocompleteController?.boundHandleInput,
    );

    // Restore focus event listener
    this.replaceEventListener(
      this.autocompleteController?.inputTarget,
      "focus",
      this.boundHandleInitialFocusWithHierarchy,
      this.autocompleteController?.boundHandleInitialFocus,
    );

    super.disconnect();
  }

  handleInputWithHierarchy(event) {
    const query = event.target.value.trim();

    this.updateClearButtonVisibilityWithHierarchy();

    // Clear last query if current query is different
    if (query !== this.autocompleteController.lastSearchQuery) {
      this.autocompleteController.lastSearchQuery = null;
    }

    // Reset keyboard navigation state when new input triggers search
    this.autocompleteController.keyboardNavigating = false;
    this.autocompleteController.updateKeyboardNavigationClass();

    // Get group config once for this entire method
    const remoteConfig = this.getCurrentGroupRemoteConfig();
    // Respect explicit 0 for minLength; only fall back when undefined
    const minLength =
      remoteConfig && remoteConfig.minLength !== undefined
        ? remoteConfig.minLength
        : this.autocompleteController.minLengthValue;

    if (query.length < minLength) {
      if (query.length === 0) {
        // For hierarchical mode, show current level items when input is empty
        this.searchLocalDataWithHierarchy("");
      } else {
        // Only close if alwaysShow is not enabled
        if (!this.autocompleteController.alwaysShowValue) {
          this.autocompleteController.close();
        }
      }
      return;
    }

    // Handle local-only searches immediately (no delay needed)
    if (!remoteConfig?.url && !this.autocompleteController.urlValue) {
      this.searchLocalDataWithHierarchy(query);
      return;
    }

    // Clear existing timeout for remote searches
    if (this.autocompleteController.searchTimeout) clearTimeout(this.autocompleteController.searchTimeout);

    // Show loading state for remote searches only if not already loading
    if (remoteConfig && remoteConfig.url && !this.autocompleteController.isLoading) {
      this.showLoadingWithGroupConfig();
    } else if (this.autocompleteController.urlValue && !this.autocompleteController.isLoading) {
      this.autocompleteController.showLoading();
    }

    // Debounce only remote searches using group-specific delay or fall back to controller delay
    const delayValue = remoteConfig?.delay || this.autocompleteController.delayValue;

    this.autocompleteController.searchTimeout = setTimeout(() => {
      // Check if the input value has changed since this timeout was scheduled
      const currentQuery = this.autocompleteController.inputTarget.value.trim();
      if (currentQuery !== query) {
        // Input has changed, don't execute this outdated search
        // The new input value should have already triggered its own handler
        return;
      }

      if (remoteConfig && remoteConfig.url) {
        // Any group with remote config should use performHybridSearchWithHierarchy
        this.performHybridSearchWithHierarchy(query);
      } else if (this.autocompleteController.urlValue) {
        // Fallback to global remote search if no group config
        this.autocompleteController.fetchSuggestions(query);
      } else {
        // Local-only search
        this.searchLocalDataWithHierarchy(query);
      }
    }, delayValue);
  }

  handleInitialFocusWithHierarchy() {
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
        this.handleInputWithHierarchy({ target: this.autocompleteController.inputTarget });
      }
    } else {
      // Check for remote search configuration for current group
      const remoteConfig = this.getCurrentGroupRemoteConfig();

      // Determine if we should trigger remote search based on group config or global config
      const shouldTriggerRemoteSearch =
        remoteConfig &&
        remoteConfig.url &&
        (remoteConfig.searchOnFocus === true ||
          (this.autocompleteController.searchOnFocusValue && remoteConfig.minLength === 0));

      if (shouldTriggerRemoteSearch) {
        // Show loading state first
        this.showLoadingWithGroupConfig();

        // Cancel any existing search timeout
        if (this.autocompleteController.searchTimeout) {
          clearTimeout(this.autocompleteController.searchTimeout);
        }

        // Trigger remote search with delay
        const delay = remoteConfig.delay || this.autocompleteController.delayValue;
        this.autocompleteController.searchTimeout = setTimeout(() => {
          // Only proceed if input is still empty and dropdown is open
          if (this.autocompleteController.inputTarget.value.trim() === "" && this.autocompleteController.isOpen) {
            this.performHybridSearchWithHierarchy("");
          }
        }, delay);
      } else {
        // For hierarchical mode without remote search, show current level items
        this.searchLocalDataWithHierarchy("");
      }
    }
  }

  searchLocalDataWithHierarchy(query) {
    const currentData = this.getCurrentLevelData();

    // For hierarchical navigation, show all current level items when query is empty
    if (!query || query.trim() === "") {
      const suggestions = currentData.slice(0, this.autocompleteController.maxSuggestionsValue);
      this.displaySuggestionsWithHierarchy(suggestions, query);
      return;
    }

    // If not hierarchical or query is present, use core's matching logic
    const suggestions = currentData
      .filter((item) => {
        // Handle simple strings
        if (typeof item === "string") {
          return this.autocompleteController.matchesQuery(item, query);
        }

        // Handle objects with search keys
        return this.autocompleteController.searchKeysValue.some((key) => {
          const value = item[key];
          return value && this.autocompleteController.matchesQuery(value.toString(), query);
        });
      })
      .slice(0, this.autocompleteController.maxSuggestionsValue);

    this.displaySuggestionsWithHierarchy(suggestions, query);
  }

  async performHybridSearchWithHierarchy(query) {
    // Get local results immediately using hierarchical data
    const localResults = this.getLocalResultsWithHierarchy(query);

    // Check if query meets minimum length requirement for remote search
    const remoteConfig = this.getCurrentGroupRemoteConfig();
    const minLength =
      remoteConfig?.minLength !== undefined ? remoteConfig.minLength : this.autocompleteController.minLengthValue;
    const shouldFetchRemote = query.length >= minLength;

    if (!shouldFetchRemote) {
      // Only show local results if query is too short for remote search
      this.displaySuggestionsWithHierarchy(localResults, query);
      return;
    }

    // If no remote config for current group, only show local results
    if (!remoteConfig || !remoteConfig.url) {
      this.displaySuggestionsWithHierarchy(localResults, query);
      return;
    }
    // For hybrid searches, don't show local results immediately - wait for remote
    // This keeps the loading state visible until we have all results

    // Cancel previous request safely
    if (this.autocompleteController.abortController && !this.autocompleteController.abortController.signal.aborted) {
      try {
        this.autocompleteController.abortController.abort();
      } catch (error) {
        // Ignore abort errors
      }
    }
    this.autocompleteController.abortController = new AbortController();

    try {
      const url = new URL(remoteConfig.url, window.location.origin);
      url.searchParams.set("q", query);

      const response = await fetch(url, {
        signal: this.autocompleteController.abortController.signal,
        headers: {
          Accept: "application/json",
        },
      });

      if (!response.ok) throw new Error("Network response was not ok");

      const data = await response.json();
      const remoteResults = data.suggestions || data;

      // Combine results: local first, then remote
      this.displayHybridSuggestionsWithHierarchy(localResults, remoteResults, query);
    } catch (error) {
      // Silently handle AbortError - this is expected when requests are cancelled
      if (error.name === "AbortError") {
        return; // Just return, don't show any results or errors
      }

      console.error("Autocomplete fetch error:", error);
      // Show local results even if remote fails
      this.displaySuggestionsWithHierarchy(localResults, query);
    }
  }

  getLocalResultsWithHierarchy(query) {
    const currentData = this.getCurrentLevelData();

    // For hierarchical navigation, show all current level items when query is empty
    if (!query || query.trim() === "") {
      return currentData.slice(0, this.autocompleteController.maxSuggestionsValue);
    }

    // If not hierarchical or query is present, use core's matching logic
    return currentData
      .filter((item) => {
        // Handle simple strings
        if (typeof item === "string") {
          return this.autocompleteController.matchesQuery(item, query);
        }

        // Handle objects with search keys
        return this.autocompleteController.searchKeysValue.some((key) => {
          const value = item[key];
          return value && this.autocompleteController.matchesQuery(value.toString(), query);
        });
      })
      .slice(0, this.autocompleteController.maxSuggestionsValue);
  }

  displayHybridSuggestionsWithHierarchy(localResults, remoteResults, query) {
    // Track the last search query
    this.autocompleteController.lastSearchQuery = query;

    if ((!localResults || localResults.length === 0) && (!remoteResults || remoteResults.length === 0)) {
      this.showNoResultsWithGroupConfig();
      return;
    }

    this.autocompleteController.isLoading = false; // End loading state
    let html = "";
    let indexOffset = 0;

    // Add local results first (hierarchical)
    if (localResults && localResults.length > 0) {
      html += this.renderSuggestionsWithHierarchy(localResults, query, indexOffset);
      indexOffset += localResults.length;
    }

    // Add separator if we have both local and remote results
    if (localResults && localResults.length > 0 && remoteResults && remoteResults.length > 0) {
      html += this.renderSeparatorWithGroupConfig();
    }

    // Add remote results (non-hierarchical but will use overridden selectSuggestion)
    if (remoteResults && remoteResults.length > 0) {
      html += this.autocompleteController.renderSuggestions(remoteResults, query, indexOffset);
    }

    this.autocompleteController.resultsTarget.innerHTML = html;
    this.autocompleteController.open();

    // Check if we should highlight a previously selected item
    this.highlightPreviousSelection();

    // Auto-select first suggestion if enabled, we have any results, not currently keyboard navigating, and user is actively searching
    const totalResults = (localResults?.length || 0) + (remoteResults?.length || 0);
    if (
      this.autocompleteController.autoSelectFirstValue &&
      totalResults > 0 &&
      !this.autocompleteController.keyboardNavigating &&
      query &&
      query.length > 0
    ) {
      this.autocompleteController.selectedIndex = 0;
      this.autocompleteController.updateSelection();
    }

    // Scroll to top for better UX in hybrid search results
    this.scrollResultsToTop();
  }

  renderSuggestionsWithHierarchy(suggestions, query, startIndex = 0) {
    return this.renderSuggestions(suggestions, query, startIndex, {
      showParentIndicator: true,
    });
  }

  getCurrentLevelData() {
    if (this.currentPath.length === 0) {
      return this.autocompleteController.localDataValue;
    }

    // Navigate to current path in hierarchical data
    let currentLevel = this.originalLocalData;
    for (const pathItem of this.currentPath) {
      const parentItem = currentLevel.find(
        (item) => (typeof item === "string" ? item : item.title || item.name || item.label) === pathItem,
      );
      if (parentItem && parentItem.children) {
        currentLevel = parentItem.children;
      } else {
        return [];
      }
    }
    return currentLevel;
  }

  displaySuggestionsWithHierarchy(suggestions, query) {
    // Track the last search query
    this.autocompleteController.lastSearchQuery = query;

    if (!suggestions || suggestions.length === 0) {
      this.showNoResultsWithGroupConfig();
      return;
    }

    this.autocompleteController.isLoading = false; // End loading state
    const html = this.renderSuggestions(suggestions, query, 0, {
      showParentIndicator: true,
    });

    this.autocompleteController.resultsTarget.innerHTML = html;
    this.autocompleteController.open();

    // Check if we should highlight a previously selected item
    this.highlightPreviousSelection();

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

    // Scroll to top for better UX when displaying new hierarchical level
    this.scrollResultsToTop();
  }

  selectSuggestionWithHierarchy(event) {
    const value = event.currentTarget.dataset.value;
    const isParent = event.currentTarget.dataset.isParent === "true";

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

    if (isParent) {
      // Prevent the click from bubbling up and triggering click-outside (only for real events)
      if (event && event.stopPropagation) {
        event.stopPropagation();
        event.preventDefault();
      }
      // Navigate into parent/folder - keep dropdown open
      this.navigateInto(suggestionData);
      return;
    }

    // Update input based on URL presence and preserveSearchOnSelect setting (for non-parent items)
    const hasUrl = suggestionData.url || suggestionData.route || suggestionData.href;
    const shouldUpdateInput = !hasUrl || (hasUrl && !this.autocompleteController.preserveSearchOnSelectValue);
    if (shouldUpdateInput) {
      this.autocompleteController.inputTarget.value = value;
      this.updateClearButtonVisibilityWithHierarchy();
    }

    // Only close if closeOnSelect is enabled AND we're not selecting a URL (or preserveSearchOnSelect is enabled)
    // For command palettes, we usually want to keep them open when selecting URLs
    const shouldClose =
      this.autocompleteController.closeOnSelectValue &&
      !(hasUrl && this.autocompleteController.preserveSearchOnSelectValue);
    if (shouldClose) this.autocompleteController.close();

    // Store the selected value for later highlighting
    this.autocompleteController.lastSelectedValue = value;

    // Execute configured action if specified
    this.autocompleteController.executeConfiguredAction(suggestionData);

    // Navigate to URL if present (automatic behavior)
    this.autocompleteController.navigateToUrl(suggestionData);

    // Dispatch custom event with full data
    this.autocompleteController.dispatch("select", {
      detail: {
        value,
        data: suggestionData,
        path: this.currentPath,
      },
    });

    // Submit if enabled
    if (this.autocompleteController.submitOnSelectValue) {
      this.autocompleteController.submitSearch(value);
    }
  }

  navigateInto(parentItem) {
    const parentTitle =
      typeof parentItem === "string" ? parentItem : parentItem.title || parentItem.name || parentItem.label;
    this.currentPath.push(parentTitle);

    // Track the icon for this level
    const iconData = this.getIconDataForItem(parentItem);
    this.currentPathIcons.push(iconData);

    // Update placeholder if the group has a custom placeholder
    if (parentItem.placeholder) {
      this.autocompleteController.inputTarget.placeholder = parentItem.placeholder;
    }

    // Clear input and show children
    this.autocompleteController.inputTarget.value = "";
    this.updateClearButtonVisibilityWithHierarchy();

    // Clear last query and selected value since we're changing context
    this.autocompleteController.lastSearchQuery = null;
    this.autocompleteController.lastSelectedValue = null;

    // Reset loading state when navigating to a new group
    this.autocompleteController.isLoading = false;

    // Reset selection index
    this.autocompleteController.selectedIndex = -1;

    // Update breadcrumb
    this.updateBreadcrumb();

    // Check if we should trigger remote search for empty query
    const remoteConfig = this.getCurrentGroupRemoteConfig();
    const shouldTriggerRemoteSearch =
      remoteConfig &&
      remoteConfig.url &&
      (remoteConfig.minLength === 0 || remoteConfig.minLength === undefined || remoteConfig.searchOnFocus === true);

    if (shouldTriggerRemoteSearch) {
      // Show loading state first for better UX
      if (remoteConfig && remoteConfig.url) {
        this.showLoadingWithGroupConfig();
      }

      // Cancel any existing search timeout
      if (this.autocompleteController.searchTimeout) {
        clearTimeout(this.autocompleteController.searchTimeout);
      }

      // Trigger remote search with empty query, respecting delay but making it cancelable
      const delay = remoteConfig?.delay || this.autocompleteController.delayValue;
      this.autocompleteController.searchTimeout = setTimeout(() => {
        // Only proceed if input is still empty (user hasn't started typing)
        // and we're still in the same hierarchical context
        if (this.autocompleteController.inputTarget.value.trim() === "" && this.autocompleteController.isOpen) {
          this.performHybridSearchWithHierarchy("");
        }
      }, delay);
    } else {
      // Trigger new search with empty query to show all children
      this.searchLocalDataWithHierarchy("");
    }

    // Ensure dropdown stays open and focus stays on input
    this.autocompleteController.inputTarget.focus();
  }

  navigateBack() {
    if (this.currentPath.length === 0) return;

    this.currentPath.pop();
    this.currentPathIcons.pop(); // Remove the icon for the level we're leaving

    // Update placeholder to the parent level's placeholder or original
    this.updatePlaceholder();

    // Clear input and search
    this.autocompleteController.inputTarget.value = "";
    this.updateClearButtonVisibilityWithHierarchy();

    // Clear last query since we're changing context
    this.autocompleteController.lastSearchQuery = null;

    // Reset loading state when navigating back
    this.autocompleteController.isLoading = false;

    // Reset selection index
    this.autocompleteController.selectedIndex = -1;

    // Update breadcrumb
    this.updateBreadcrumb();

    // Show parent level
    this.searchLocalDataWithHierarchy("");

    // Keep dropdown open and focus on input
    this.autocompleteController.inputTarget.focus();
  }

  updateClearButtonVisibilityWithHierarchy() {
    if (this.autocompleteController.hasClearButtonTarget) {
      // Show clear button if there's text in input OR if we're in a nested level
      const hasInput = this.autocompleteController.inputTarget.value;
      const hasNesting = this.currentPath.length > 0;

      if (hasInput || hasNesting) {
        this.autocompleteController.clearButtonTarget.classList.remove("hidden");
        this.autocompleteController.clearButtonTarget.classList.add("flex");
      } else {
        this.autocompleteController.clearButtonTarget.classList.add("hidden");
        this.autocompleteController.clearButtonTarget.classList.remove("flex");
      }
    }
  }

  updatePlaceholder() {
    if (this.currentPath.length === 0) {
      // At root level, use original placeholder
      this.autocompleteController.inputTarget.placeholder = this.originalPlaceholder;
      return;
    }

    // Navigate to current parent and get its placeholder
    let currentLevel = this.originalLocalData;
    let currentGroup = null;

    for (const pathItem of this.currentPath) {
      const parentItem = currentLevel.find(
        (item) => (typeof item === "string" ? item : item.title || item.name || item.label) === pathItem,
      );
      if (parentItem && parentItem.children) {
        currentGroup = parentItem;
        currentLevel = parentItem.children;
      } else {
        break;
      }
    }

    // Use the current group's placeholder or fall back to original
    if (currentGroup && currentGroup.placeholder) {
      this.autocompleteController.inputTarget.placeholder = currentGroup.placeholder;
    } else {
      this.autocompleteController.inputTarget.placeholder = this.originalPlaceholder;
    }
  }

  clearInputWithHierarchy() {
    // If we're in a nested level, reset to root and clear input
    if (this.currentPath.length > 0) {
      this.currentPath = [];
      this.currentPathIcons = []; // Clear all icon data
      this.autocompleteController.inputTarget.value = "";

      // Restore original placeholder when returning to root
      this.autocompleteController.inputTarget.placeholder = this.originalPlaceholder;

      // Update breadcrumb
      this.updateBreadcrumb();

      this.autocompleteController.close();
      this.updateClearButtonVisibilityWithHierarchy();
      this.autocompleteController.lastSearchQuery = null;
      this.autocompleteController.inputTarget.focus();
    } else {
      // If not nested, just clear the input normally
      this.autocompleteController.inputTarget.value = "";
      this.autocompleteController.close();
      this.updateClearButtonVisibilityWithHierarchy();
      this.autocompleteController.lastSearchQuery = null;
      this.autocompleteController.inputTarget.focus();
    }
  }

  getCurrentGroupRemoteConfig() {
    if (this.currentPath.length === 0) {
      // At root level, use main autocomplete controller configuration or check for root-level remote config
      const rootConfig = this.getRootGroupRemoteConfig();
      return (
        rootConfig || {
          url: this.autocompleteController.urlValue,
          delay: this.autocompleteController.delayValue,
          loadingText: this.autocompleteController.loadingTextValue,
          noResultsText: this.autocompleteController.noResultsTextValue,
          minLength: this.autocompleteController.minLengthValue,
          separatorText: this.autocompleteController.separatorTextValue,
        }
      );
    }

    // Navigate to current group and get its remote configuration
    let currentLevel = this.originalLocalData;
    let currentGroup = null;

    for (const pathItem of this.currentPath) {
      const parentItem = currentLevel.find(
        (item) => (typeof item === "string" ? item : item.title || item.name || item.label) === pathItem,
      );
      if (parentItem && parentItem.children) {
        currentGroup = parentItem;
        currentLevel = parentItem.children;
      } else {
        return null;
      }
    }

    // Return the remote configuration for the current group
    return currentGroup ? currentGroup.remoteConfig : null;
  }

  getRootGroupRemoteConfig() {
    // Check if the root level data has a remoteConfig
    if (this.originalLocalData && this.originalLocalData.length > 0) {
      // Look for a special root configuration object
      const rootConfig = this.originalLocalData.find(
        (item) => item && typeof item === "object" && item._rootRemoteConfig,
      );
      return rootConfig ? rootConfig.remoteConfig : null;
    }
    return null;
  }

  showLoadingWithGroupConfig() {
    // Don't re-render if already loading
    if (this.autocompleteController.isLoading) {
      return;
    }

    this.autocompleteController.isLoading = true; // Set loading state
    const remoteConfig = this.getCurrentGroupRemoteConfig();
    const loadingText = remoteConfig?.loadingText || this.autocompleteController.loadingTextValue;

    this.autocompleteController.resultsTarget.innerHTML = `
      <div class="px-4 py-8 text-center">
        <div class="inline-flex items-center gap-2 text-sm text-neutral-500 dark:text-neutral-400">
          <svg class="animate-spin size-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          ${loadingText}
        </div>
      </div>
    `;
    this.autocompleteController.open();
    this.scrollResultsToTop();
  }

  showNoResultsWithGroupConfig() {
    this.autocompleteController.isLoading = false; // End loading state
    const remoteConfig = this.getCurrentGroupRemoteConfig();
    const noResultsText = remoteConfig?.noResultsText || this.autocompleteController.noResultsTextValue;

    this.autocompleteController.resultsTarget.innerHTML = `
      <div class="px-4 py-8 text-center text-sm text-neutral-500 dark:text-neutral-400">
        ${noResultsText}
      </div>
    `;
    this.autocompleteController.open();
    this.scrollResultsToTop();
  }

  renderSeparatorWithGroupConfig() {
    const remoteConfig = this.getCurrentGroupRemoteConfig();
    const separatorText = remoteConfig?.separatorText || this.autocompleteController.separatorTextValue;

    return `
      <div class="px-4 pt-3 pb-1.5 border-t border-neutral-200 dark:border-neutral-700">
        <div class="text-xs font-medium text-neutral-500 dark:text-neutral-400 uppercase tracking-wide">
          ${separatorText}
        </div>
      </div>
    `;
  }

  closeWithHierarchy() {
    if (!this.autocompleteController.isOpen) return;

    // If alwaysShow is enabled, don't actually close - just reset to current hierarchical level
    if (this.autocompleteController.alwaysShowValue) {
      // Reset to current hierarchical level instead of closing
      this.searchLocalDataWithHierarchy("");
      return;
    }

    // For non-hierarchical or when alwaysShow is disabled, use original close behavior
    this.originalClose();
  }

  updateBreadcrumb() {
    if (!this.breadcrumbValue || !this.hasBreadcrumbTarget) return;

    const breadcrumbElement = this.breadcrumbTarget;

    if (this.currentPath.length === 0) {
      // At root level, hide breadcrumb or show just home
      breadcrumbElement.innerHTML = this.renderHomeBreadcrumb();
      return;
    }

    // Build breadcrumb with home + current path
    let breadcrumbHtml = this.renderHomeBreadcrumb();

    this.currentPath.forEach((pathItem, index) => {
      const isLast = index === this.currentPath.length - 1;
      breadcrumbHtml += this.renderBreadcrumbItem(pathItem, index, isLast);
    });

    breadcrumbElement.innerHTML = breadcrumbHtml;
  }

  renderHomeBreadcrumb() {
    const isActive = this.currentPath.length === 0;

    if (isActive) {
      // Active state - at root level
      return `
        <div class="flex items-center text-sm">
          <span class="flex gap-1.5 items-center text-neutral-900 dark:text-neutral-100 p-1.5" aria-current="page">
            <svg xmlns="http://www.w3.org/2000/svg" class="size-4 shrink-0" width="18" height="18" viewBox="0 0 18 18"><g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" stroke="currentColor"><path d="M14.855 5.95L9.605 1.96C9.247 1.688 8.752 1.688 8.395 1.96L3.145 5.95C2.896 6.139 2.75 6.434 2.75 6.747V14.251C2.75 15.356 3.645 16.251 4.75 16.251H7.25V12.251C7.25 11.699 7.698 11.251 8.25 11.251H9.75C10.302 11.251 10.75 11.699 10.75 12.251V16.251H13.25C14.355 16.251 15.25 15.356 15.25 14.251V6.746C15.25 6.433 15.104 6.14 14.855 5.95Z"></path></g></svg>
            <span>Home</span>
          </span>
        </div>
      `;
    } else {
      // Inactive state - can navigate back to root
      return `
        <div class="flex items-center text-sm">
          <button type="button"
                  class="flex gap-1.5 items-center text-neutral-500 hover:text-neutral-700 dark:text-neutral-400 dark:hover:text-neutral-200 transition-colors p-1.5 rounded hover:bg-black/5 dark:hover:bg-white/5 focus-visible:outline-2 focus-visible:outline-offset-0 focus-visible:outline-neutral-600 dark:focus-visible:outline-neutral-200"
                  data-action="click->autocomplete-navigation#navigateToLevel"
                  data-level="-1">
            <svg xmlns="http://www.w3.org/2000/svg" class="size-4 shrink-0" width="18" height="18" viewBox="0 0 18 18"><g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" stroke="currentColor"><path d="M14.855 5.95L9.605 1.96C9.247 1.688 8.752 1.688 8.395 1.96L3.145 5.95C2.896 6.139 2.75 6.434 2.75 6.747V14.251C2.75 15.356 3.645 16.251 4.75 16.251H7.25V12.251C7.25 11.699 7.698 11.251 8.25 11.251H9.75C10.302 11.251 10.75 11.699 10.75 12.251V16.251H13.25C14.355 16.251 15.25 15.356 15.25 14.251V6.746C15.25 6.433 15.104 6.14 14.855 5.95Z"></path></g></svg>
            <span>Home</span>
          </button>
        </div>
      `;
    }
  }

  renderBreadcrumbItem(pathItem, index, isLast) {
    const separator = `
      <svg xmlns="http://www.w3.org/2000/svg" class="size-4 shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd"></path>
      </svg>
    `;

    // Get icon for this level
    const iconData = this.currentPathIcons[index] || { icon: "folder", customIcon: null };
    const iconSvg = iconData.customIcon || this.autocompleteController.getIconSvg(iconData.icon);

    if (isLast) {
      return `
        <div class="flex items-center text-sm">
          ${separator}
          <span class="flex items-center gap-1.5 text-neutral-900 dark:text-neutral-100 p-1.5" aria-current="page">
            ${iconSvg}
            ${this.escapeHtml(pathItem)}
          </span>
        </div>
      `;
    } else {
      return `
        <div class="flex items-center text-sm">
          ${separator}
          <button type="button"
                  class="flex items-center gap-1.5 text-neutral-500 hover:text-neutral-700 dark:text-neutral-400 dark:hover:text-neutral-200 transition-colors p-1.5 rounded hover:bg-black/5 dark:hover:bg-white/5 focus-visible:outline-2 focus-visible:outline-offset-0 focus-visible:outline-neutral-600 dark:focus-visible:outline-neutral-200"
                  data-action="click->autocomplete-navigation#navigateToLevel"
                  data-level="${index}">
            ${iconSvg}
            ${this.escapeHtml(pathItem)}
          </button>
        </div>
      `;
    }
  }

  navigateToLevel(event) {
    const targetLevel = parseInt(event.currentTarget.dataset.level);

    if (targetLevel === -1) {
      // Navigate to root
      this.currentPath = [];
      this.currentPathIcons = [];
    } else if (targetLevel >= 0 && targetLevel < this.currentPath.length) {
      // Navigate to specific level
      this.currentPath = this.currentPath.slice(0, targetLevel + 1);
      this.currentPathIcons = this.currentPathIcons.slice(0, targetLevel + 1);
    }

    // Update placeholder
    this.updatePlaceholder();

    // Clear input and search
    this.autocompleteController.inputTarget.value = "";
    this.updateClearButtonVisibilityWithHierarchy();

    // Clear last query since we're changing context
    this.autocompleteController.lastSearchQuery = null;

    // Reset loading state when navigating to a different level
    this.autocompleteController.isLoading = false;

    // Reset selection index
    this.autocompleteController.selectedIndex = -1;

    // Update breadcrumb
    this.updateBreadcrumb();

    // Show the level
    this.searchLocalDataWithHierarchy("");

    // Keep dropdown open and focus on input
    this.autocompleteController.inputTarget.focus();
  }

  getIconDataForItem(item) {
    if (typeof item === "string") {
      return { icon: "folder", customIcon: null };
    }

    return {
      icon: item.icon || "folder",
      customIcon: item.customIcon || null,
    };
  }

  scrollResultsToTop() {
    // Scroll the results container to the top for better UX when changing hierarchical levels
    if (this.autocompleteController.resultsTarget) {
      this.autocompleteController.resultsTarget.scrollTop = 0;
    }
  }

  highlightPreviousSelection() {
    // Only highlight if we have a previously selected value and input is empty
    if (!this.autocompleteController.lastSelectedValue || this.autocompleteController.inputTarget.value.trim() !== "") {
      return;
    }

    const suggestions = this.autocompleteController.suggestionTargets;
    for (let i = 0; i < suggestions.length; i++) {
      const suggestion = suggestions[i];
      const suggestionValue = suggestion.dataset.value;

      if (suggestionValue === this.autocompleteController.lastSelectedValue) {
        // Found the previously selected item - highlight it
        this.autocompleteController.selectedIndex = i;
        this.autocompleteController.updateSelection();

        // Scroll the highlighted item into view after DOM updates
        setTimeout(() => {
          suggestion.scrollIntoView({
            block: "nearest",
            behavior: "smooth",
          });
        }, 50);
        break;
      }
    }
  }

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }
}
