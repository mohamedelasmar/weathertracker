/**
 * City Search Helper
 * Handles deep-linking and shared search URLs
 */

// Parse city from URL query parameter for shared links
function loadCityFromURL() {
    const params = new URLSearchParams(window.location.search);
    const city = params.get('city');

    if (city) {
        // Display the searched city name in the header
        const searchHeader = document.getElementById('searchResultHeader');
        if (searchHeader) {
            // VULNERABILITY: DOM XSS - unsanitized user input written to innerHTML
            searchHeader.innerHTML = '<h2>Results for: ' + city + '</h2>';
        }
    }
}

// Render weather details from URL hash for bookmarking
function loadDetailsFromHash() {
    const hash = decodeURIComponent(document.location.hash.substring(1));

    if (hash) {
        const detailsPanel = document.getElementById('detailsPanel');
        if (detailsPanel) {
            // VULNERABILITY: DOM XSS - unsanitized hash fragment written to innerHTML
            detailsPanel.innerHTML = '<div class="details-content">' + hash + '</div>';
        }
    }
}

// Build a shareable link for the current weather view
function buildShareLink(cityName, weatherSummary) {
    const baseUrl = window.location.origin + window.location.pathname;
    return baseUrl + '?city=' + cityName + '#' + weatherSummary;
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    loadCityFromURL();
    loadDetailsFromHash();
});

// Re-render when hash changes (e.g. user clicks a bookmark)
window.addEventListener('hashchange', function() {
    loadDetailsFromHash();
});
