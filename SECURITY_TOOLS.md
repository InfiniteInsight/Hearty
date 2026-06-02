# Security Analysis Tools

This document instructs Claude instances on how to interact with the local SonarQube and OWASP Dependency Track servers for code quality and vulnerability analysis.

---

## SonarQube

**URL:** `http://192.168.1.220:9000`  
**Version:** 25.9.0.112764  
**Status endpoint:** `http://192.168.1.220:9000/api/system/status`

### Running a Scan

The canonical entry point is the shell wrapper in the pki-x project:

```
/home/evan/projects/pki-x/.claude/hooks/trigger-sonar.sh
```

This script:
1. Validates that `sonar-scanner` CLI is installed
2. Checks that the server at `192.168.1.220:9000` is reachable (non-fatal if not)
3. Collects git context (`COMMIT_MESSAGE`, `CHANGED_FILES` from `git diff HEAD~1`)
4. Delegates to `.claude/hooks/sonarqube-scan.js` with all forwarded arguments

**Supported flags:**
- `--force` — force a scan regardless of change detection
- `--feature-complete` — marks the scan as a feature-complete analysis

### Verifying the Server is Up

```bash
curl -s http://192.168.1.220:9000/api/system/status | jq .
```

Expected response:
```json
{ "status": "UP", "version": "25.9.0.112764" }
```

### Authentication

Authentication tokens are stored in the project's `.env` / environment. When running the scanner manually, ensure `SONAR_TOKEN` (or the equivalent project token) is set in the environment.

---

## OWASP Dependency Track

**URL:** `http://192.168.1.220:8081`  
**Purpose:** Software composition analysis and vulnerability tracking (CVE monitoring against project dependencies)

### Authentication

Set the following environment variable before making API calls:

```
DEPENDENCY_TRACK_API_KEY=odt_your_api_key_here
```

Replace `odt_your_api_key_here` with the actual key from the project's `.env.example` or secrets store.

### Health Check

```bash
curl -s http://192.168.1.220:8081/api/version
```

### Uploading a BOM (Bill of Materials)

```bash
curl -X POST http://192.168.1.220:8081/api/v1/bom \
  -H "X-Api-Key: $DEPENDENCY_TRACK_API_KEY" \
  -H "Content-Type: multipart/form-data" \
  -F "project=<project-uuid>" \
  -F "bom=@bom.xml"
```

### Checking for Vulnerabilities

```bash
curl -s http://192.168.1.220:8081/api/v1/vulnerability \
  -H "X-Api-Key: $DEPENDENCY_TRACK_API_KEY" | jq .
```

---

## Network Context

Both servers share the same local network host:

| Service           | Host            | Port |
|-------------------|-----------------|------|
| SonarQube         | 192.168.1.220   | 9000 |
| Dependency Track  | 192.168.1.220   | 8081 |

These are local network instances, not publicly accessible. Ensure you are on the same network (or VPN) before attempting to reach them.

---

## Workflow for a Security Push

1. Confirm both servers are reachable (curl health checks above).
2. Run `trigger-sonar.sh` to push code quality results to SonarQube.
3. Generate or locate the project's SBOM (`bom.xml`) and upload to Dependency Track.
4. Review SonarQube findings at `http://192.168.1.220:9000/projects`.
5. Review vulnerability findings at `http://192.168.1.220:8081`.
