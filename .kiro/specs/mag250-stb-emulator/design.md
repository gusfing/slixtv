# Design Document: MAG250 STB Emulator

## Overview

This design document specifies the technical architecture for transforming the existing Flutter IPTV mobile application into a full MAG250 Set-Top Box (STB) emulator. The system will achieve exact protocol parity with real MAG250/STBEmu clients, making the application indistinguishable from physical STB devices when communicating with Stalker/Ministra middleware servers.

### Design Goals

1. **Protocol Fidelity**: Exact replication of MAG250 HTTP headers, request patterns, and response handling
2. **Session Integrity**: Centralized session management with persistent authentication state
3. **Content Compatibility**: Support for Live TV, Movies, and Series with all metadata variations
4. **Resilience**: Graceful handling of protocol anomalies, middleware variations, and network errors
5. **Debuggability**: Comprehensive diagnostic tools for protocol verification and troubleshooting
6. **Maintainability**: Clean separation of concerns with well-defined component boundaries

### Scope

**In Scope:**
- Device identity generation and persistence
- MAG protocol implementation (authentication, content fetching, stream resolution)
- Session management with cookie persistence
- Multi-format response parsing (JSON, XML, HTML)
- Content engines for Live TV, Movies, and Series
- Video player header injection
- Debug dashboard with protocol diagnostics
- Structured logging system
- Error recovery mechanisms

**Out of Scope:**
- UI/UX modifications (existing UI is preserved)
- New content features beyond Live TV, Movies, and Series
- Custom middleware extensions
- DRM or encryption handling
- Offline playback capabilities

## Architecture

### High-Level Architecture

The system follows a layered architecture with clear separation between protocol, session, content, and presentation layers:

```mermaid
graph TB
    UI[UI Layer - Existing Flutter Widgets]
    ContentEngines[Content Engines Layer]
    Protocol[MAG Protocol Layer]
    Session[Session Management Layer]
    Network[Network Layer - HTTP Client]
    Storage[Storage Layer - Secure Storage]
    Player[Video Player Layer]
    Debug[Debug Dashboard]

    UI --> ContentEngines
    UI --> Debug
    ContentEngines --> Protocol
    Protocol --> Session
    Protocol --> Network
    Session --> Storage
    Player --> Session
    Debug --> Session
    Debug --> Protocol
    
    ContentEngines -.->|Live TV| Protocol
    ContentEngines -.->|Movies| Protocol
    ContentEngines -.->|Series| Protocol
