# Implementation Plan: MAG250 STB Emulator

## Overview

This implementation plan transforms the existing Flutter IPTV application into a full MAG250 Set-Top Box emulator with exact protocol parity. The implementation follows a layered architecture: Device Identity → Session Management → Protocol Layer → Content Engines → Player Integration → Debug Tools.

## Tasks

- [ ] 1. Set up core project structure and device identity
  - [ ] 1.1 Create MAG250 device identity generator and storage
    - Create `lib/features/mag_emulator/data/models/device_identity.dart` with fields: MAC, serial, device_id, device_id2, signature, hw_version, image_version, stb_type, model
    - Implement MAC generation with "00:1A:79:XX:XX:XX" format
    - Implement serial number derivation from MAC (12 uppercase alphanumeric)
    - Implement device_id and device_id2 as 32-char lowercase hex strings
    - Use flutter_secure_storage to persist device identity
    - Implement load/save/regenerate methods
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.11, 1.12_

  - [ ]* 1.2 Write unit tests for device identity generator
    - Test MAC format validation
    - Test serial number derivation
    - Test persistence and loading
    - Test regeneration functionality
    - _Requirements: 1.1-1.12_

- [ ] 2. Implement centralized session management
  - [ ] 2.1 Create session manager singleton
    - Create `lib/features/mag_emulator/data/services/session_manager.dart`
    - Implement singleton pattern with factory constructor
    - Add fields: bearerToken, portalBaseUrl, portalEndpoint, macAddress
    - Integrate CookieJar with persistent storage using cookie_jar package
    - Implement methods: setBearerToken, getBearerToken, clearSession, hasValidSession
    - Implement cookie persistence to disk
    - Implement cookie restoration on app restart
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10, 3.11, 3.12_

  - [ ]* 2.2 Write unit tests for session manager
    - Test singleton instance
    - Test token storage and retrieval
    - Test session clearing
    - Test cookie persistence
    - _Requirements: 3.1-3.12_

- [ ] 3. Implement MAG protocol HTTP headers
  - [ ] 3.1 Create MAG protocol headers builder
    - Create `lib/features/mag_emulator/data/services/mag_headers.dart`
    - Implement buildHeaders method that returns Map<String, String>
    - Set User-Agent: "Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3"
    - Set X-User-Agent: "Model: MAG250; Link: WiFi"
    - Set Accept: "*/*"
    - Set Accept-Language: "en_US"
    - Set Accept-Encoding: "gzip, deflate"
    - Set Connection: "keep-alive"
    - Set Referer based on portal base URL
    - Set Cookie with MAC address and timezone
    - Set Authorization with Bearer token when available
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10_

  - [ ]* 3.2 Write unit tests for headers builder
    - Test all required headers are present
    - Test header values match MAG250 format
    - Test Authorization header with and without token
    - Test Cookie header formatting
    - _Requirements: 2.1-2.10_

- [ ] 4. Implement portal endpoint discovery
  - [ ] 4.1 Create portal endpoint discovery service
    - Create `lib/features/mag_emulator/data/services/portal_discovery.dart`
    - Implement URL normalization (add http://, remove trailing slashes)
    - Implement candidate path testing in order: /server/load.php, /stalker_portal/server/load.php, /portal.php, /load.php
    - Send handshake request (type=stb, action=handshake) to each candidate
    - Check for HTTP 200 with JSON response containing "js" field
    - Default to /stalker_portal/server/load.php if all fail
    - Store discovered endpoint in SessionManager
    - Implement 15-second total timeout
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9, 4.10, 4.11, 4.12_

  - [ ]* 4.2 Write unit tests for portal discovery
    - Test URL normalization
    - Test candidate path ordering
    - Test successful discovery
    - Test fallback to default
    - _Requirements: 4.1-4.12_

- [ ] 5. Checkpoint - Verify foundation components
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Implement MAG authentication flow
  - [ ] 6.1 Create MAG authentication service
    - Create `lib/features/mag_emulator/data/services/mag_auth_service.dart`
    - Implement 5-step bootstrap sequence:
      - Step 1: handshake (action=handshake, prehash=0)
      - Step 2: get_profile (action=get_profile)
      - Step 3: get_main_info (action=get_main_info)
      - Step 4: get_modules (action=get_modules)
      - Step 5: mark session as authenticated
    - Extract token from handshake response (js.token)
    - Store token in SessionManager
    - Extract and store user profile data (id, name, mac, ip)
    - Extract and store server info (server_name)
    - Handle HTTP 401 with authentication exception
    - Handle network errors with descriptive exceptions
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 5.10, 5.11, 5.12_

  - [ ]* 6.2 Write unit tests for authentication service
    - Test successful 5-step sequence
    - Test token extraction and storage
    - Test HTTP 401 handling
    - Test network error handling
    - _Requirements: 5.1-5.12_

- [ ] 7. Implement multi-format response parser
  - [ ] 7.1 Create response parser utility
    - Create `lib/features/mag_emulator/data/utils/response_parser.dart`
    - Implement parseResponse method accepting HTTP response
    - Handle Content-Type: application/json → parse as JSON
    - Handle Content-Type: text/xml or application/xml → parse as XML
    - Handle Content-Type: text/html → extract JSON from HTML
    - Handle String body → attempt JSON parse, wrap in {"js": value} if fails
    - Handle Map body → use directly
    - Handle js=false or js=null → treat as empty data
    - Return empty Map with js=false on complete parsing failure
    - Log all parsing attempts and results
    - Extract error messages from PHP error HTML
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8, 9.9, 9.10, 9.11, 9.12_

  - [ ]* 7.2 Write unit tests for response parser
    - Test JSON parsing
    - Test XML parsing
    - Test HTML with embedded JSON
    - Test String wrapping
    - Test js=false and js=null handling
    - Test error extraction from PHP HTML
    - _Requirements: 9.1-9.12_

- [ ] 8. Implement create_link resolution engine
  - [ ] 8.1 Create stream URL resolver
    - Create `lib/features/mag_emulator/data/services/stream_resolver.dart`
    - Implement command prefix stripping: "ffmpeg ", "ffrt3 ", "ffrt ", "auto ", "/ch/"
    - Extract URL from "http" position in mixed strings
    - Select first valid HTTP/RTSP URL from space-separated list
    - Bypass create_link for direct HTTP/HTTPS URLs
    - Replace localhost/127.0.0.1 with portal host
    - Log warnings for unsupported schemes (udp://, rtsp://)
    - Send create_link request with type, action, cmd, series parameters
    - Extract Stream_URL from js.cmd or js.url field
    - Handle js.error="nothing_to_play" with user-friendly exception
    - Throw exception for empty/invalid URLs
    - Follow HTTP redirects up to 5 times
    - Apply prefix stripping to create_link responses
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 10.8, 10.9, 10.10, 10.11, 10.12, 10.13, 10.14, 10.15, 10.16_

  - [ ]* 8.2 Write unit tests for stream resolver
    - Test prefix stripping for all formats
    - Test URL extraction from mixed strings
    - Test localhost replacement
    - Test direct URL bypass
    - Test nothing_to_play error handling
    - _Requirements: 10.1-10.16_

- [ ] 9. Checkpoint - Verify protocol layer
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 10. Implement Live TV content engine
  - [ ] 10.1 Create Live TV service
    - Create `lib/features/mag_emulator/data/services/live_tv_service.dart`
    - Implement getCategories: type=itv, action=get_genres
    - Handle js as List → parse directly
    - Handle js as Map with "data" field → extract data
    - Handle js=false or js=null → return empty list
    - Implement getAllChannels: type=itv, action=get_all_channels
    - Implement getChannelsByCategory: type=itv, action=get_ordered_list, genre={category_id}
    - Implement getEPG: type=itv, action=get_short_epg, ch_id={channel_id}
    - Implement createPlaybackLink: type=itv, action=create_link, cmd={channel_cmd}
    - Parse channel data: id, name, number, logo, cmd
    - Parse EPG data: id, name, time, time_to, t_time
    - Resolve relative logo URLs against portal base
    - Handle PHP associative array format (Map with numeric string keys)
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 6.9, 6.10, 6.11, 6.12_

  - [ ]* 10.2 Write unit tests for Live TV service
    - Test category fetching with different response formats
    - Test channel fetching
    - Test EPG fetching
    - Test playback link creation
    - Test logo URL resolution
    - _Requirements: 6.1-6.12_

- [ ] 11. Implement Movies content engine
  - [ ] 11.1 Create Movies service
    - Create `lib/features/mag_emulator/data/services/movies_service.dart`
    - Implement getCategories: type=vod, action=get_categories
    - Implement getMoviesByCategory: type=vod, action=get_ordered_list, category={id}, p={page}, sortby={sort}
    - Default sortby to "added" if not specified
    - Implement getMovieMetadata: type=vod, action=get_info, movie_id={id}
    - Implement createPlaybackLink: type=vod, action=create_link, cmd={movie_cmd}
    - Parse movie data: id, name, description, director, actors, year, rating, poster
    - Resolve poster URLs with priority: cover_big, cover, poster, screenshot_uri, icon, logo, image
    - Resolve relative poster URLs against portal base
    - Calculate total pages: ceil(total_items / max_page_items)
    - Select first file with valid HTTP URL from files array
    - Handle PHP associative array format
    - Handle js as Map, List, false, or null
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10, 7.11, 7.12_

  - [ ]* 11.2 Write unit tests for Movies service
    - Test category fetching
    - Test movie list fetching with pagination
    - Test metadata fetching
    - Test poster URL resolution priority
    - Test file selection from array
    - _Requirements: 7.1-7.12_

- [ ] 12. Implement Series content engine
  - [ ] 12.1 Create Series service
    - Create `lib/features/mag_emulator/data/services/series_service.dart`
    - Implement getCategories: type=series, action=get_categories
    - Implement getSeriesByCategory: type=series, action=get_ordered_list, category={id}, p={page}
    - Implement getSeriesMetadata: type=series, action=get_info, series_id={id}
    - Implement getSeasonData: type=series, action=get_ordered_list, season_id={id}, series_id={series_id}
    - Implement createPlaybackLink: type=series, action=create_link, cmd={episode_cmd}, series={series_id}
    - Parse series data: id, name, description, actors, director, year, poster
    - Parse season data as nested objects with season_number and episodes array
    - Parse season data as flat episode lists with season field
    - Parse season data as Map-based structures with season IDs as keys
    - Parse episode data: id, name, season, episode, cmd, time
    - Resolve poster URLs with same priority as movies
    - Normalize multiple season structures to consistent format
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9, 8.10, 8.11, 8.12_

  - [ ]* 12.2 Write unit tests for Series service
    - Test category fetching
    - Test series list fetching
    - Test metadata fetching
    - Test season data parsing (all three formats)
    - Test episode data parsing
    - _Requirements: 8.1-8.12_

- [ ] 13. Checkpoint - Verify content engines
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 14. Implement video player header injection
  - [ ] 14.1 Create player headers injection service
    - Create `lib/features/mag_emulator/data/services/player_headers_service.dart`
    - Implement getPlayerHeaders method returning Map<String, String>
    - Inject Authorization header with current Bearer token
    - Inject Cookie header with MAC address
    - Inject User-Agent matching MAG250
    - Inject X-User-Agent matching MAG250
    - Inject Referer with portal base URL
    - Configure video_player to use headers on Android (ExoPlayer)
    - Configure video_player to use headers on iOS (AVPlayer)
    - Apply headers to both initial requests and segment requests
    - Omit Authorization header when token not available
    - Log all injected headers for debugging
    - Log warning for HTTP 403 playback failures
    - Support both HLS and MPEG-DASH formats
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7, 11.8, 11.9, 11.10, 11.11, 11.12_

  - [ ]* 14.2 Write unit tests for player headers service
    - Test header generation with token
    - Test header generation without token
    - Test header format matching MAG250
    - _Requirements: 11.1-11.12_

- [ ] 15. Implement structured logging system
  - [ ] 15.1 Create MAG protocol logger
    - Create `lib/features/mag_emulator/data/services/mag_logger.dart`
    - Log request method (GET/POST)
    - Log full URL
    - Log all query parameters
    - Log all headers (mask token to first 16 chars)
    - Log request body if present
    - Log HTTP status code
    - Log response time in milliseconds
    - Log first 200 characters of response body
    - Log error type and message on failure
    - Assign unique request ID for correlation
    - Use tag "NETWORK" for general requests
    - Use tag "MAG:{action}" for MAG-specific actions
    - Store logs in circular buffer (max 500 entries)
    - Implement export as plain text and JSON
    - Use ISO 8601 timestamps
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6, 13.7, 13.8, 13.9, 13.10, 13.11, 13.12, 13.13, 13.14, 13.15_

  - [ ]* 15.2 Write unit tests for logger
    - Test log entry creation
    - Test circular buffer behavior
    - Test token masking
    - Test export formats
    - _Requirements: 13.1-13.15_

- [ ] 16. Implement error recovery mechanisms
  - [ ] 16.1 Create error handler service
    - Create `lib/features/mag_emulator/data/services/error_handler.dart`
    - Handle HTTP 401: attempt re-authentication once, retry original request
    - Throw authentication exception if re-auth fails
    - Handle HTTP 429: throw "Rate limited. Please wait and try again."
    - Handle timeout: throw "Connection timeout - check your network"
    - Handle connection error: throw "Cannot reach portal server"
    - Parse XML when JSON expected
    - Extract error messages from HTML error pages
    - Handle nothing_to_play with user-friendly message
    - Log playback errors and provide retry option
    - Log warning for Cookie_Jar persistence failures
    - Log warning for Portal_Endpoint discovery failures
    - Never crash application for network/parsing errors
    - Provide specific error messages for each failure type
    - Store last critical error for Debug Dashboard
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5, 14.6, 14.7, 14.8, 14.9, 14.10, 14.11, 14.12, 14.13, 14.14, 14.15_

  - [ ]* 16.2 Write unit tests for error handler
    - Test HTTP 401 re-authentication flow
    - Test HTTP 429 handling
    - Test timeout handling
    - Test connection error handling
    - Test error message extraction
    - _Requirements: 14.1-14.15_

- [ ] 17. Implement configuration parser and pretty printer
  - [ ] 17.1 Create configuration utilities
    - Create `lib/features/mag_emulator/data/utils/config_parser.dart`
    - Parse get_main_info: server_name, portal_name, support_url
    - Parse get_modules: available modules list
    - Parse get_profile: stb_type, timezone, locale
    - Handle missing fields with default values
    - Validate parsed values match expected types
    - Log warnings for unexpected formats
    - Create `lib/features/mag_emulator/data/utils/config_pretty_printer.dart`
    - Format Device_Identity as multi-line labeled string
    - Format Session_Manager state as multi-line labeled string
    - Format Cookie_Jar as multi-line string (one cookie per line)
    - Format log entries with timestamps and tags
    - Mask sensitive data (tokens show first 16 chars only)
    - Format JSON with 2-space indentation
    - Truncate long URLs to 80 chars with ellipsis
    - Format timestamps as "HH:mm:ss"
    - Format error stack traces with line breaks
    - Provide export as formatted JSON
    - _Requirements: 16.1, 16.2, 16.3, 16.4, 16.5, 16.6, 16.7, 16.8, 16.9, 16.10, 17.1, 17.2, 17.3, 17.4, 17.5, 17.6, 17.7, 17.8, 17.9, 17.10_

  - [ ]* 17.2 Write unit tests for configuration utilities
    - Test parsing of all configuration responses
    - Test default value handling
    - Test pretty printing formats
    - Test sensitive data masking
    - _Requirements: 16.1-16.10, 17.1-17.10_

- [ ] 18. Implement debug dashboard UI
  - [ ] 18.1 Create debug dashboard screen
    - Create `lib/features/mag_emulator/presentation/screens/debug_dashboard_screen.dart`
    - Display Device_Identity: MAC, serial, device_id, device_id2, signature, hw_version, image_version, stb_type, model
    - Display Bearer token (first 16 chars visible, rest masked)
    - Display all cookies from Cookie_Jar
    - Display discovered Portal_Endpoint
    - Display last selected content item (ID and name)
    - Display last create_link request (type, action, cmd, series)
    - Display last create_link response (raw js field)
    - Display resolved Stream_URL after prefix stripping
    - Display HTTP redirects during stream resolution
    - Display Player_Headers injected into video player
    - Display last error message and stack trace
    - Display last 100 log entries with timestamps, levels, tags, messages
    - Implement "COPY DEBUG REPORT" button → copy to clipboard
    - Implement "EXPORT JSON" button → save as JSON file
    - Implement "CLEAR LOGS" button → clear log buffer
    - Make dashboard scrollable
    - Auto-refresh when new data available
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7, 12.8, 12.9, 12.10, 12.11, 12.12, 12.13, 12.14, 12.15, 12.16, 12.17, 12.18, 12.19, 12.20_

  - [ ] 18.2 Add debug dashboard access points
    - Implement tap counter on app logo (5 rapid taps → open dashboard)
    - Implement long-press on avatar widget → open dashboard
    - Add "Developer Tools" menu item in settings screen → open dashboard
    - _Requirements: 12.1, 12.2, 12.3_

- [ ] 19. Checkpoint - Verify debug tools
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 20. Integration and wiring
  - [ ] 20.1 Wire MAG emulator into existing app
    - Create `lib/features/mag_emulator/mag_emulator_provider.dart` using Riverpod
    - Expose DeviceIdentity, SessionManager, MagAuthService, LiveTvService, MoviesService, SeriesService
    - Update existing authentication flow to use MagAuthService
    - Update existing Live TV screens to use LiveTvService
    - Update existing Movies screens to use MoviesService
    - Update existing Series screens to use SeriesService
    - Update video player initialization to use PlayerHeadersService
    - Integrate ErrorHandler into all network calls
    - Integrate MagLogger into all MAG protocol operations
    - _Requirements: All requirements_

  - [ ]* 20.2 Write integration tests
    - Test complete authentication flow
    - Test Live TV content fetching and playback
    - Test Movies content fetching and playback
    - Test Series content fetching and playback
    - Test error recovery scenarios
    - _Requirements: All requirements_

- [ ] 21. Test portal validation
  - [ ] 21.1 Validate against test portal
    - Test authentication with portal "http://tv.stream4k.cc" and MAC "00:1E:99:2C:D2:08"
    - Verify successful Live TV category fetching
    - Verify successful channel fetching
    - Verify successful movie category fetching
    - Verify successful movie fetching
    - Verify successful movie playback link resolution
    - Verify successful series category fetching
    - Verify successful series fetching
    - Verify successful episode data fetching
    - Verify successful episode playback link resolution
    - Verify no exceptions thrown during test operations
    - Verify all resolved Stream_URLs are valid HTTP/HTTPS
    - Verify Debug Dashboard displays correct information
    - Log all test portal interactions
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5, 15.6, 15.7, 15.8, 15.9, 15.10, 15.11, 15.12, 15.13, 15.14, 15.15_

- [ ] 22. Final checkpoint - Complete system verification
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- The implementation preserves the existing UI while adding MAG protocol support
- All network operations use the Dio package with cookie_jar for session management
- Video player uses the existing video_player and chewie packages
- Secure storage uses flutter_secure_storage for device identity and tokens
- Logging uses the logger package for structured logging
- The debug dashboard is accessible via multiple entry points for developer convenience

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1", "3.1"] },
    { "id": 1, "tasks": ["1.2", "2.2", "3.2", "4.1"] },
    { "id": 2, "tasks": ["4.2", "6.1", "7.1"] },
    { "id": 3, "tasks": ["6.2", "7.2", "8.1"] },
    { "id": 4, "tasks": ["8.2", "10.1", "11.1", "12.1"] },
    { "id": 5, "tasks": ["10.2", "11.2", "12.2", "14.1", "15.1", "16.1", "17.1"] },
    { "id": 6, "tasks": ["14.2", "15.2", "16.2", "17.2", "18.1"] },
    { "id": 7, "tasks": ["18.2", "20.1"] },
    { "id": 8, "tasks": ["20.2", "21.1"] }
  ]
}
```
