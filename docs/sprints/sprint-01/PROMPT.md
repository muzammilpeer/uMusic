# Sprint 01 implementation prompt

```text
Implement Sprint 01 of uMusic after verifying Sprint 00 exit criteria. Read the
project documentation and this sprint README. Build accounts and library models,
MP3 upload jobs, quarantine, content inspection, SHA-256 storage, ID3/artwork
extraction, exact duplicate handling, audit records, web pages, and REST APIs.

Only genuine MP3 audio is accepted. Validate content, not only extension or MIME.
Use transaction boundaries so failures create neither active tracks nor orphaned
permanent files. Implement a storage interface with local Docker-volume and
mounted shared POSIX filesystem backends suitable for GFS/GlusterFS. Store a
backend ID and logical object key rather than host paths. Safely handle cross-
filesystem publishing and concurrent imports.

Add non-copyrighted fixtures and tests for valid, corrupt, renamed, duplicate,
oversized, concurrent, and storage-failure cases. Run all checks and report the
Sprint 02 entry conditions.
```

