import { BaseAutocompleteExtension } from "controllers/autocomplete_controller";

export default class extends BaseAutocompleteExtension {
  static values = {
    // This controller is specifically for fuzzy search functionality
    // If you don't need fuzzy search, don't add this controller
    fuzzyThreshold: { type: Number, default: 0.1 }, // Minimum score for fuzzy matches (0-1)
  };

  initialize() {
    // Check if autocomplete controller is available before proceeding
    if (!this.autocompleteController) {
      return;
    }

    // Override the searchLocalData method for fuzzy search
    this.overrideMethod("searchLocalData", this.searchLocalDataWithFuzzy);

    // Override the highlightText method for fuzzy highlighting
    this.overrideMethod("highlightText", this.highlightTextWithFuzzy);
  }

  searchLocalDataWithFuzzy(query) {
    const currentData = this.autocompleteController.localDataValue;
    const suggestions = this.fuzzyFilter(currentData, query);
    this.autocompleteController.displaySuggestions(suggestions, query);
  }

  highlightTextWithFuzzy(text, query) {
    // Fuzzy highlighting - highlight matching characters
    return this.highlightFuzzyMatch(text, query);
  }

  // Fuzzy search implementation
  fuzzyFilter(items, query) {
    const scored = items
      .map((item) => {
        const text = typeof item === "string" ? item : item.title || item.name || item.label;
        const score = this.fuzzyScore(text.toLowerCase(), query.toLowerCase());
        return { item, score, text };
      })
      .filter((result) => result.score > this.fuzzyThresholdValue) // Filter out items with very low scores
      .sort((a, b) => b.score - a.score)
      .slice(0, this.autocompleteController.maxSuggestionsValue);

    return scored.map((result) => result.item);
  }

  fuzzyScore(text, query) {
    // Perfect match
    if (text === query) return 1.0;

    // Contains exact query
    if (text.includes(query)) return 0.9;

    // Normalize: remove spaces and convert to lowercase for better matching
    const normalizedText = text.replace(/\s+/g, "").toLowerCase();
    const normalizedQuery = query.replace(/\s+/g, "").toLowerCase();

    // Check if normalized query is contained in normalized text
    if (normalizedText.includes(normalizedQuery)) return 0.85;

    const textLen = normalizedText.length;
    const queryLen = normalizedQuery.length;

    if (queryLen === 0) return 1.0;
    if (queryLen > textLen) return 0.0;

    // Check for subsequence match with improved scoring
    let textIndex = 0;
    let queryIndex = 0;
    let matches = 0;
    let consecutiveMatches = 0;
    let maxConsecutive = 0;
    let firstMatchIndex = -1;
    let lastMatchIndex = -1;

    while (textIndex < textLen && queryIndex < queryLen) {
      if (normalizedText[textIndex] === normalizedQuery[queryIndex]) {
        if (firstMatchIndex === -1) firstMatchIndex = textIndex;
        lastMatchIndex = textIndex;
        matches++;
        consecutiveMatches++;
        maxConsecutive = Math.max(maxConsecutive, consecutiveMatches);
        queryIndex++;
      } else {
        consecutiveMatches = 0;
      }
      textIndex++;
    }

    // If not all characters were matched, return 0
    if (queryIndex < queryLen) return 0.0;

    // Calculate score with multiple factors
    const matchRatio = matches / queryLen;
    const consecutiveBonus = (maxConsecutive / queryLen) * 0.3;

    // Bonus for matches at the beginning of the text
    const startBonus = firstMatchIndex === 0 ? 0.2 : 0;

    // Penalty for spread out matches (compactness bonus)
    const matchSpread = lastMatchIndex - firstMatchIndex + 1;
    const compactBonus = Math.max(0, (queryLen - matchSpread + queryLen) / (textLen * 2)) * 0.2;

    // Small penalty for length difference
    const lengthPenalty = Math.abs(queryLen - textLen) / (textLen * 10);

    return Math.max(0, Math.min(1.0, matchRatio + consecutiveBonus + startBonus + compactBonus - lengthPenalty));
  }

  highlightFuzzyMatch(text, query) {
    const lowerText = text.toLowerCase();
    // Remove spaces from query for fuzzy matching
    const normalizedQuery = query.replace(/\s+/g, "").toLowerCase();
    const result = [];
    let textIndex = 0;
    let queryIndex = 0;

    while (textIndex < text.length) {
      const currentChar = lowerText[textIndex];

      // Skip spaces in the original text when matching, but include them in output
      if (currentChar === " ") {
        result.push(text[textIndex]);
        textIndex++;
        continue;
      }

      if (queryIndex < normalizedQuery.length && currentChar === normalizedQuery[queryIndex]) {
        // This character matches the query
        result.push(`<mark class="bg-yellow-200 dark:bg-yellow-400 font-medium">${text[textIndex]}</mark>`);
        queryIndex++;
      } else {
        // Regular character
        result.push(text[textIndex]);
      }
      textIndex++;
    }

    return result.join("");
  }
}
