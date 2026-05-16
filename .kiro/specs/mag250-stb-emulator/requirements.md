# Requirements Document: MAG250 STB Emulator

## Introduction

This document specifies the requirements for transforming the existing Flutter IPTV mobile application into a full MAG250 Set-Top Box (STB) emulator client. The goal is to achieve exact protocol parity with real MAG250/STBEmu clients, making the application indistinguishable from a physical STB device when communicating with Stalker/Ministra middleware servers.

The transformation focuses exclusively on the authentication, session management, protocol implementation, and playback layers while preserving the existing UI and user experience. The application must handle all protocol anomalies, edge cases, and middleware variations that real MAG250 devices encounter in production environments.

## Glossary

- **STB**: Set-Top Box - A physical device (MAG250) that connects to IPTV services
- **Stalker_Middleware**: The server-side portal software (Ministra/Stalker) that manages IPTV content
- **MAG_Protocol**: The specific HTTP-based communication protocol used by MAG devices
- **Session_Manager**: Centralized service managing authentication state, tokens, and cookies
- **Device_Identity**: The unique identifiers (MAC, serial, device_id) that identify an STB
- **Portal_Endpoint**: The server URL path (e.g., /server/load.php) that handles API requests
- **Create_Link**: The API action that resolves content commands to playable stream URLs
- **Bearer_Token**: The authentication token received during handshake and used in subsequent requests
- **Cookie_Jar**: Persistent storage for HTTP cookies including MAC address
- **Player_Headers**: HTTP headers injected into video playback requests
- **Debug_Dashboard**: Developer interface showing protocol state and diagnostics
- **Content_Command**: The cmd field from content metadata (e.g., "ffmpeg http://..." or "/media/123.mpg")
- **Stream_URL**: The final resolved HTTP/RTSP URL that the video player uses
- **EPG**: Electronic Program Guide - TV schedule information
- **VOD**: Video On Demand - Movies and recorded content
- **Series_Metadata**: Hierarchical data structure containing seasons and episodes

## Requirements

### Requirement 1: STB Device Identity Generation and Persistence

**User Story:** As a system, I want to generate and persist authentic MAG250 device identifiers, so that the Stalker_Middleware recognizes the application as a legitimate STB device.

#### Acceptance Criteria

1. WHEN the application first launches, THE Device_Identity SHALL generate a unique MAC address in the format "00:1A:79:XX:XX:XX" where X represents random hexadecimal digits
2. THE Device_Identity SHALL generate a serial number derived from the MAC address with 12 uppercase alphanumeric characters
3. THE Device_Identity SHALL generate a device_id as a 32-character lowercase hexadecimal string
4. THE Device_Identity SHALL generate a device_id2 as a 32-character lowercase hexadecimal string different from device_id
5. THE Device_Identity SHALL set signature to "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456"
6. THE Device_Identity SHALL set hw_version to "1.7-BD-00"
7. THE Device_Identity SHALL set image_version to "218"
8. THE Device_Identity SHALL set stb_type to "MAG250"
9. THE Device_Identity SHALL set model to "MAG250"
10. THE Device_Identity SHALL persist all generated identifiers to secure storage
11. WHEN the application launches after initial setup, THE Device_Identity SHALL load the persisted identifiers instead of generating new ones
12. THE Device_Identity SHALL provide a method to regenerate all identifiers when explicitly requested by the user

### Requirement 2: MAG250 HTTP Headers Emulation

**User Story:** As a network layer, I want to send exact MAG250 HTTP headers with every request, so that the Stalker_Middleware cannot distinguish the application from a real MAG250 device.

#### Acceptance Criteria

1. THE MAG_Protocol SHALL set User-Agent header to "Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3"
2. THE MAG_Protocol SHALL set X-User-Agent header to "Model: MAG250; Link: WiFi"
3. THE MAG_Protocol SHALL set Accept header to "*/*"
4. THE MAG_Protocol SHALL set Accept-Language header to "en_US"
5. THE MAG_Protocol SHALL set Accept-Encoding header to "gzip, deflate"
6. THE MAG_Protocol SHALL set Connection header to "keep-alive"
7. WHEN a portal base URL is configured, THE MAG_Protocol SHALL set Referer header to "{portal_base}/c/"
8. WHEN a MAC address is configured, THE MAG_Protocol SHALL set Cookie header to "mac={url_encoded_mac}; stb_lang=en; timezone=Asia/Kolkata" on every request
9. WHEN a Bearer_Token is available, THE MAG_Protocol SHALL set Authorization header to "Bearer {token}"
10. THE MAG_Protocol SHALL apply these headers to all Stalker_Middleware requests without exception

### Requirement 3: Centralized Session Management

**User Story:** As a session manager, I want to maintain all authentication state in one place, so that all features have consistent access to tokens, cookies, and portal configuration.

#### Acceptance Criteria

1. THE Session_Manager SHALL maintain a singleton instance accessible throughout the application
2. THE Session_Manager SHALL store the current Bearer_Token
3. THE Session_Manager SHALL store the portal base URL
4. THE Session_Manager SHALL store the discovered Portal_Endpoint path
5. THE Session_Manager SHALL store the MAC address
6. THE Session_Manager SHALL maintain a Cookie_Jar with persistent storage
7. THE Session_Manager SHALL provide methods to set and retrieve the Bearer_Token
8. THE Session_Manager SHALL provide methods to clear all session data
9. WHEN session data is cleared, THE Session_Manager SHALL delete all cookies from the Cookie_Jar
10. THE Session_Manager SHALL provide methods to check if a valid session exists
11. THE Session_Manager SHALL persist the Cookie_Jar to disk after each modification
12. WHEN the application restarts, THE Session_Manager SHALL restore the Cookie_Jar from disk

### Requirement 4: Portal Endpoint Discovery

**User Story:** As an authentication system, I want to automatically discover the correct portal endpoint from multiple candidates, so that the application works with different Stalker_Middleware configurations.

#### Acceptance Criteria

1. WHEN a portal URL is provided, THE Portal_Endpoint SHALL normalize it by adding "http://" if no scheme is present
2. THE Portal_Endpoint SHALL remove trailing slashes from the normalized URL
3. THE Portal_Endpoint SHALL attempt to discover the endpoint by testing candidate paths in order
4. THE Portal_Endpoint SHALL test "{portal_url}/server/load.php" as the first candidate
5. THE Portal_Endpoint SHALL test "{portal_url}/stalker_portal/server/load.php" as the second candidate
6. THE Portal_Endpoint SHALL test "{portal_url}/portal.php" as the third candidate
7. THE Portal_Endpoint SHALL test "{portal_url}/load.php" as the fourth candidate
8. WHEN testing a candidate, THE Portal_Endpoint SHALL send a handshake request with type=stb and action=handshake
9. WHEN a candidate returns HTTP 200 with a JSON response containing a "js" field, THE Portal_Endpoint SHALL select that candidate as the valid endpoint
10. WHEN no candidate succeeds, THE Portal_Endpoint SHALL default to "{portal_url}/stalker_portal/server/load.php"
11. THE Portal_Endpoint SHALL store the discovered endpoint in the Session_Manager
12. THE Portal_Endpoint SHALL complete discovery within 15 seconds total timeout

### Requirement 5: MAG Session Bootstrap Sequence

**User Story:** As an authentication flow, I want to execute the exact 5-step MAG bootstrap sequence, so that the session is properly initialized with the Stalker_Middleware.

#### Acceptance Criteria

1. WHEN authentication begins, THE MAG_Protocol SHALL execute step 1: handshake with action=handshake and prehash=0
2. WHEN handshake succeeds, THE MAG_Protocol SHALL extract the token from the response js.token field
3. WHEN the token is extracted, THE MAG_Protocol SHALL store it in the Session_Manager
4. WHEN handshake succeeds, THE MAG_Protocol SHALL execute step 2: get_profile with action=get_profile
5. WHEN get_profile succeeds, THE MAG_Protocol SHALL extract user profile data including id, name, mac, and ip
6. WHEN get_profile succeeds, THE MAG_Protocol SHALL execute step 3: get_main_info with action=get_main_info
7. WHEN get_main_info succeeds, THE MAG_Protocol SHALL extract server information including server_name
8. WHEN get_main_info succeeds, THE MAG_Protocol SHALL execute step 4: get_modules with action=get_modules
9. WHEN get_modules succeeds, THE MAG_Protocol SHALL extract available module information
10. THE MAG_Protocol SHALL mark the session as authenticated after all steps complete successfully
11. IF any step fails with HTTP 401, THE MAG_Protocol SHALL throw an authentication exception
12. IF any step fails with a network error, THE MAG_Protocol SHALL throw a network exception with a descriptive message

### Requirement 6: Live TV Content Engine

**User Story:** As a live TV feature, I want to fetch categories, channels, EPG data, and playback links using the MAG protocol, so that users can watch live television.

#### Acceptance Criteria

1. WHEN fetching live TV categories, THE MAG_Protocol SHALL send a request with type=itv and action=get_genres
2. WHEN the category response contains js as a List, THE MAG_Protocol SHALL parse it directly as categories
3. WHEN the category response contains js as a Map with a "data" field, THE MAG_Protocol SHALL extract the data field and parse it as categories
4. WHEN the category response contains js=false or js=null, THE MAG_Protocol SHALL return an empty category list
5. WHEN fetching all channels, THE MAG_Protocol SHALL send a request with type=itv and action=get_all_channels
6. WHEN fetching channels by category, THE MAG_Protocol SHALL send a request with type=itv, action=get_ordered_list, and genre={category_id}
7. WHEN fetching EPG for a channel, THE MAG_Protocol SHALL send a request with type=itv, action=get_short_epg, and ch_id={channel_id}
8. WHEN creating a playback link for live TV, THE MAG_Protocol SHALL send a request with type=itv, action=create_link, and cmd={channel_cmd}
9. THE MAG_Protocol SHALL parse channel data including id, name, number, logo, and cmd fields
10. THE MAG_Protocol SHALL parse EPG data including id, name, time, time_to, and t_time fields
11. THE MAG_Protocol SHALL resolve relative logo URLs against the portal base URL
12. WHEN a channel list response uses PHP associative array format (Map with numeric string keys), THE MAG_Protocol SHALL extract the values as a List

### Requirement 7: Movies Content Engine

**User Story:** As a movies feature, I want to fetch categories, movie lists, metadata, and playback links using the MAG protocol, so that users can watch on-demand movies.

#### Acceptance Criteria

1. WHEN fetching movie categories, THE MAG_Protocol SHALL send a request with type=vod and action=get_categories
2. WHEN fetching movies by category, THE MAG_Protocol SHALL send a request with type=vod, action=get_ordered_list, category={category_id}, p={page}, and sortby={sort_field}
3. WHEN fetching movie metadata, THE MAG_Protocol SHALL send a request with type=vod, action=get_info, and movie_id={movie_id}
4. WHEN creating a playback link for a movie, THE MAG_Protocol SHALL send a request with type=vod, action=create_link, and cmd={movie_cmd}
5. THE MAG_Protocol SHALL parse movie data including id, name, description, director, actors, year, rating, poster fields
6. THE MAG_Protocol SHALL resolve poster URLs by checking cover_big, cover, poster, screenshot_uri, icon, logo, and image fields in priority order
7. THE MAG_Protocol SHALL resolve relative poster URLs against the portal base URL
8. WHEN a movie list response contains total_items and max_page_items fields, THE MAG_Protocol SHALL calculate total pages as ceil(total_items / max_page_items)
9. WHEN a movie has multiple files in a files array, THE MAG_Protocol SHALL select the first file with a valid HTTP URL
10. WHEN the movie metadata response uses PHP associative array format, THE MAG_Protocol SHALL extract values correctly
11. THE MAG_Protocol SHALL handle movie responses where js is a Map, List, false, or null
12. WHEN sortby is not specified, THE MAG_Protocol SHALL default to "added"

### Requirement 8: Series Content Engine

**User Story:** As a series feature, I want to fetch categories, series lists, season/episode metadata, and playback links using the MAG protocol, so that users can watch TV series.

#### Acceptance Criteria

1. WHEN fetching series categories, THE MAG_Protocol SHALL send a request with type=series and action=get_categories
2. WHEN fetching series by category, THE MAG_Protocol SHALL send a request with type=series, action=get_ordered_list, category={category_id}, and p={page}
3. WHEN fetching series metadata, THE MAG_Protocol SHALL send a request with type=series, action=get_info, and series_id={series_id}
4. WHEN fetching season data, THE MAG_Protocol SHALL send a request with type=series, action=get_ordered_list, season_id={season_id}, and series_id={series_id}
5. WHEN creating a playback link for an episode, THE MAG_Protocol SHALL send a request with type=series, action=create_link, cmd={episode_cmd}, and series={series_id}
6. THE MAG_Protocol SHALL parse series data including id, name, description, actors, director, year, poster fields
7. THE MAG_Protocol SHALL parse season data as nested objects with season_number and episodes array
8. THE MAG_Protocol SHALL parse season data as flat episode lists with season field
9. THE MAG_Protocol SHALL parse season data as Map-based structures with season IDs as keys
10. THE MAG_Protocol SHALL parse episode data including id, name, season, episode, cmd, and time fields
11. THE MAG_Protocol SHALL resolve poster URLs using the same priority as movies
12. WHEN series metadata contains multiple season structures, THE MAG_Protocol SHALL normalize them to a consistent format

### Requirement 9: Response Parser with Multi-Format Support

**User Story:** As a response parser, I want to handle JSON, XML, HTML, and plain text responses without crashing, so that the application works with all Stalker_Middleware variations.

#### Acceptance Criteria

1. WHEN a response has Content-Type "application/json", THE MAG_Protocol SHALL parse it as JSON
2. WHEN a response has Content-Type "text/xml" or "application/xml", THE MAG_Protocol SHALL parse it as XML
3. WHEN a response has Content-Type "text/html", THE MAG_Protocol SHALL extract JSON from HTML if present
4. WHEN a response body is a String, THE MAG_Protocol SHALL attempt to parse it as JSON
5. WHEN JSON parsing fails, THE MAG_Protocol SHALL wrap the string in a js field: {"js": string_value}
6. WHEN a response body is already a Map, THE MAG_Protocol SHALL use it directly
7. WHEN a response contains a js field with value false, THE MAG_Protocol SHALL treat it as empty data
8. WHEN a response contains a js field with value null, THE MAG_Protocol SHALL treat it as empty data
9. THE MAG_Protocol SHALL not throw exceptions for unexpected response formats
10. WHEN parsing fails completely, THE MAG_Protocol SHALL return an empty Map with js=false
11. THE MAG_Protocol SHALL log all parsing attempts and results
12. WHEN a response contains PHP error HTML, THE MAG_Protocol SHALL extract error messages if possible

### Requirement 10: Create Link Resolution Engine

**User Story:** As a stream resolver, I want to normalize content commands and resolve them to playable URLs, so that the video player receives valid stream links.

#### Acceptance Criteria

1. WHEN a Content_Command starts with "ffmpeg ", THE MAG_Protocol SHALL strip the prefix and extract the URL
2. WHEN a Content_Command starts with "ffrt3 ", THE MAG_Protocol SHALL strip the prefix and extract the URL
3. WHEN a Content_Command starts with "ffrt ", THE MAG_Protocol SHALL strip the prefix and extract the URL
4. WHEN a Content_Command starts with "auto ", THE MAG_Protocol SHALL strip the prefix and extract the URL
5. WHEN a Content_Command starts with "/ch/", THE MAG_Protocol SHALL strip the prefix and extract the URL
6. WHEN a Content_Command contains "http" after other text, THE MAG_Protocol SHALL extract everything from "http" onward
7. WHEN a Content_Command contains multiple space-separated URLs, THE MAG_Protocol SHALL select the first valid HTTP/RTSP URL
8. WHEN a Content_Command is already a valid HTTP/HTTPS URL, THE MAG_Protocol SHALL bypass create_link and use it directly
9. WHEN a Content_Command contains "localhost" or "127.0.0.1", THE MAG_Protocol SHALL replace it with the portal host
10. WHEN a Content_Command uses unsupported schemes (udp://, rtsp://), THE MAG_Protocol SHALL log a warning and attempt resolution anyway
11. WHEN create_link returns a response with js.cmd field, THE MAG_Protocol SHALL use that as the Stream_URL
12. WHEN create_link returns a response with js.url field and no cmd field, THE MAG_Protocol SHALL use js.url as the Stream_URL
13. WHEN create_link returns js.error="nothing_to_play", THE MAG_Protocol SHALL throw an exception with message "This content is currently unavailable"
14. WHEN create_link returns an empty or invalid URL, THE MAG_Protocol SHALL throw an exception with message "Could not resolve stream URL"
15. THE MAG_Protocol SHALL follow HTTP redirects up to 5 times when resolving Stream_URLs
16. THE MAG_Protocol SHALL apply the same prefix stripping to create_link responses as to original commands

### Requirement 11: Video Player Header Injection

**User Story:** As a video player, I want to inject MAG protocol headers into playback requests, so that the stream server accepts the connection.

#### Acceptance Criteria

1. WHEN initializing video playback, THE Player_Headers SHALL inject the Authorization header with the current Bearer_Token
2. WHEN initializing video playback, THE Player_Headers SHALL inject the Cookie header with the MAC address
3. WHEN initializing video playback, THE Player_Headers SHALL inject the User-Agent header matching MAG250
4. WHEN initializing video playback, THE Player_Headers SHALL inject the X-User-Agent header matching MAG250
5. WHEN initializing video playback, THE Player_Headers SHALL inject the Referer header with the portal base URL
6. THE Player_Headers SHALL configure ExoPlayer on Android to use these headers
7. THE Player_Headers SHALL configure AVPlayer on iOS to use these headers
8. THE Player_Headers SHALL apply headers to both initial requests and segment requests
9. WHEN a Bearer_Token is not available, THE Player_Headers SHALL omit the Authorization header
10. THE Player_Headers SHALL log all injected headers for debugging
11. WHEN playback fails with HTTP 403, THE Player_Headers SHALL log a warning about possible authentication issues
12. THE Player_Headers SHALL support both HLS and MPEG-DASH stream formats

### Requirement 12: Debug Dashboard Implementation

**User Story:** As a developer, I want to access a comprehensive debug dashboard, so that I can diagnose protocol issues and verify correct MAG emulation.

#### Acceptance Criteria

1. WHEN the user taps the app logo 5 times rapidly, THE Debug_Dashboard SHALL open
2. WHERE the app has an avatar widget, WHEN the user long-presses it, THE Debug_Dashboard SHALL open
3. WHERE the app has a settings screen, THE Debug_Dashboard SHALL be accessible from a "Developer Tools" menu item
4. THE Debug_Dashboard SHALL display the current Device_Identity including MAC, serial, device_id, device_id2, signature, hw_version, image_version, stb_type, and model
5. THE Debug_Dashboard SHALL display the current Bearer_Token (first 16 characters visible, rest masked)
6. THE Debug_Dashboard SHALL display all current cookies from the Cookie_Jar
7. THE Debug_Dashboard SHALL display the discovered Portal_Endpoint
8. THE Debug_Dashboard SHALL display the last selected content item (movie/series/channel) with its ID and name
9. THE Debug_Dashboard SHALL display the last create_link request including type, action, cmd, and series parameters
10. THE Debug_Dashboard SHALL display the last create_link response including the raw js field
11. THE Debug_Dashboard SHALL display the resolved Stream_URL after prefix stripping
12. THE Debug_Dashboard SHALL display any HTTP redirects that occurred during stream resolution
13. THE Debug_Dashboard SHALL display the Player_Headers that were injected into the video player
14. THE Debug_Dashboard SHALL display the last error message and stack trace if available
15. THE Debug_Dashboard SHALL provide a "COPY DEBUG REPORT" button that copies all information to clipboard
16. THE Debug_Dashboard SHALL provide an "EXPORT JSON" button that saves all information as a JSON file
17. THE Debug_Dashboard SHALL provide a "CLEAR LOGS" button that clears the log buffer
18. THE Debug_Dashboard SHALL display the last 100 log entries with timestamps, levels, tags, and messages
19. THE Debug_Dashboard SHALL auto-refresh when new data is available
20. THE Debug_Dashboard SHALL be scrollable to accommodate all information

### Requirement 13: Structured Request Logging

**User Story:** As a logging system, I want to log every network request with structured data, so that developers can trace protocol interactions.

#### Acceptance Criteria

1. WHEN a network request is initiated, THE MAG_Protocol SHALL log the request method (GET/POST)
2. WHEN a network request is initiated, THE MAG_Protocol SHALL log the full URL
3. WHEN a network request is initiated, THE MAG_Protocol SHALL log all query parameters
4. WHEN a network request is initiated, THE MAG_Protocol SHALL log all headers (with token masked)
5. WHEN a network request is initiated, THE MAG_Protocol SHALL log the request body if present
6. WHEN a network response is received, THE MAG_Protocol SHALL log the HTTP status code
7. WHEN a network response is received, THE MAG_Protocol SHALL log the response time in milliseconds
8. WHEN a network response is received, THE MAG_Protocol SHALL log the first 200 characters of the response body
9. WHEN a network request fails, THE MAG_Protocol SHALL log the error type and message
10. THE MAG_Protocol SHALL assign a unique request ID to each request for correlation
11. THE MAG_Protocol SHALL log requests with tag "NETWORK" and appropriate log level
12. THE MAG_Protocol SHALL log MAG-specific actions (handshake, get_profile, create_link) with tag "MAG:{action}"
13. THE MAG_Protocol SHALL store logs in a circular buffer with maximum 500 entries
14. THE MAG_Protocol SHALL provide methods to export logs as plain text and JSON
15. THE MAG_Protocol SHALL include timestamps in ISO 8601 format for all log entries

### Requirement 14: Error Recovery and Resilience

**User Story:** As an error handler, I want to gracefully recover from common protocol errors, so that users experience minimal disruption.

#### Acceptance Criteria

1. WHEN a request returns HTTP 401, THE MAG_Protocol SHALL attempt to re-authenticate once automatically
2. WHEN re-authentication succeeds, THE MAG_Protocol SHALL retry the original request
3. WHEN re-authentication fails, THE MAG_Protocol SHALL throw an authentication exception
4. WHEN a request returns HTTP 429 (rate limit), THE MAG_Protocol SHALL throw an exception with message "Rate limited. Please wait and try again."
5. WHEN a request times out, THE MAG_Protocol SHALL throw an exception with message "Connection timeout - check your network"
6. WHEN a request fails with connection error, THE MAG_Protocol SHALL throw an exception with message "Cannot reach portal server"
7. WHEN a JSON response is expected but XML is received, THE MAG_Protocol SHALL attempt to parse the XML
8. WHEN an HTML error page is received, THE MAG_Protocol SHALL extract error messages from the HTML
9. WHEN create_link returns nothing_to_play, THE MAG_Protocol SHALL throw a user-friendly exception
10. WHEN video playback fails, THE MAG_Protocol SHALL log the error and provide a retry option
11. WHEN the Cookie_Jar fails to persist, THE MAG_Protocol SHALL log a warning but continue operation
12. WHEN the Portal_Endpoint discovery fails for all candidates, THE MAG_Protocol SHALL use a default endpoint and log a warning
13. THE MAG_Protocol SHALL not crash the application for any network or parsing error
14. THE MAG_Protocol SHALL provide specific error messages for each failure type
15. THE MAG_Protocol SHALL store the last critical error in the Debug_Dashboard

### Requirement 15: Test Portal Validation

**User Story:** As a quality assurance process, I want to validate the implementation against a known test portal, so that protocol correctness is verified.

#### Acceptance Criteria

1. THE MAG_Protocol SHALL successfully authenticate with portal URL "http://tv.stream4k.cc"
2. THE MAG_Protocol SHALL successfully authenticate with MAC address "00:1E:99:2C:D2:08"
3. WHEN authenticated with the test portal, THE MAG_Protocol SHALL successfully fetch live TV categories
4. WHEN authenticated with the test portal, THE MAG_Protocol SHALL successfully fetch at least one channel
5. WHEN authenticated with the test portal, THE MAG_Protocol SHALL successfully fetch movie categories
6. WHEN authenticated with the test portal, THE MAG_Protocol SHALL successfully fetch at least one movie
7. WHEN authenticated with the test portal, THE MAG_Protocol SHALL successfully resolve a movie playback link
8. WHEN authenticated with the test portal, THE MAG_Protocol SHALL successfully fetch series categories
9. WHEN authenticated with the test portal, THE MAG_Protocol SHALL successfully fetch at least one series
10. WHEN authenticated with the test portal, THE MAG_Protocol SHALL successfully fetch episode data for a series
11. WHEN authenticated with the test portal, THE MAG_Protocol SHALL successfully resolve an episode playback link
12. THE MAG_Protocol SHALL complete all test portal operations without throwing exceptions
13. THE MAG_Protocol SHALL log all test portal interactions for verification
14. THE MAG_Protocol SHALL verify that resolved Stream_URLs are valid HTTP/HTTPS URLs
15. THE MAG_Protocol SHALL verify that the Debug_Dashboard displays correct information for test portal sessions

### Requirement 16: Parser for Configuration Files

**User Story:** As a developer, I want to parse MAG configuration responses, so that I can extract device settings and portal parameters.

#### Acceptance Criteria

1. WHEN a get_main_info response is received, THE Configuration_Parser SHALL parse the server_name field
2. WHEN a get_main_info response is received, THE Configuration_Parser SHALL parse the portal_name field
3. WHEN a get_main_info response is received, THE Configuration_Parser SHALL parse the support_url field
4. WHEN a get_modules response is received, THE Configuration_Parser SHALL parse the available modules list
5. WHEN a get_profile response is received, THE Configuration_Parser SHALL parse the stb_type field
6. WHEN a get_profile response is received, THE Configuration_Parser SHALL parse the timezone field
7. WHEN a get_profile response is received, THE Configuration_Parser SHALL parse the locale field
8. THE Configuration_Parser SHALL handle missing fields by providing default values
9. THE Configuration_Parser SHALL validate that parsed values match expected types
10. THE Configuration_Parser SHALL log warnings for unexpected configuration formats

### Requirement 17: Pretty Printer for Configuration Files

**User Story:** As a developer, I want to format configuration data for display, so that the Debug_Dashboard shows readable information.

#### Acceptance Criteria

1. THE Configuration_Pretty_Printer SHALL format Device_Identity as a multi-line string with labeled fields
2. THE Configuration_Pretty_Printer SHALL format Session_Manager state as a multi-line string with labeled fields
3. THE Configuration_Pretty_Printer SHALL format Cookie_Jar contents as a multi-line string with one cookie per line
4. THE Configuration_Pretty_Printer SHALL format log entries as a multi-line string with timestamps and tags
5. THE Configuration_Pretty_Printer SHALL mask sensitive data (tokens show only first 16 characters)
6. THE Configuration_Pretty_Printer SHALL format JSON responses with 2-space indentation
7. THE Configuration_Pretty_Printer SHALL truncate long URLs to 80 characters with ellipsis
8. THE Configuration_Pretty_Printer SHALL format timestamps in "HH:mm:ss" format for display
9. THE Configuration_Pretty_Printer SHALL format error stack traces with proper line breaks
10. THE Configuration_Pretty_Printer SHALL provide a method to export all data as formatted JSON

### Requirement 18: Round-Trip Property for Configuration Parsing

**User Story:** As a quality assurance process, I want to verify that configuration parsing and formatting are consistent, so that no data is lost in the process.

#### Acceptance Criteria

1. FOR ALL valid configuration responses, THE Configuration_Parser SHALL parse them into structured objects
2. FOR ALL parsed configuration objects, THE Configuration_Pretty_Printer SHALL format them into strings
3. FOR ALL formatted configuration strings, THE Configuration_Parser SHALL parse them back into equivalent objects
4. THE round-trip process SHALL preserve all field values
5. THE round-trip process SHALL preserve all field types
6. THE round-trip process SHALL complete without throwing exceptions
7. WHEN a field is missing in the original response, THE round-trip SHALL preserve the default value
8. WHEN a field contains special characters, THE round-trip SHALL preserve them correctly
9. WHEN a field contains Unicode characters, THE round-trip SHALL preserve them correctly
10. THE round-trip property SHALL be verified with at least 100 randomly generated configuration responses

