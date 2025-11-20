# Managed Cloud FTP Service - Business Plan

## Executive Summary

Offer a managed cloud FTP service as a premium subscription feature for FTPDownloader users at **$14.99/month**. The service provides 256GB storage with 24-hour automatic file cleanup, eliminating the need for users to maintain their own FTP infrastructure.

**Target:** 200 active subscribers
**Revenue:** $2,998/month ($35,976/year)
**Profit:** $1,837/month ($22,044/year) at 61% margin
**Break-even:** 7 subscribers

---

## Technical Architecture

### Infrastructure Stack

**Hosting Provider:** DigitalOcean
**FTP Server:** vsftpd (Very Secure FTP Daemon)
**Storage:** DigitalOcean Spaces (S3-compatible object storage)
**Database:** PostgreSQL (managed database for virtual users)
**Backend API:** Node.js/Python for provisioning automation

### Server Configuration

**Droplet Specifications:**
- **Size:** 2 vCPU / 4GB RAM ($24/month)
- **OS:** Ubuntu 22.04 LTS
- **Storage:** Minimal (uses object storage backend)
- **Bandwidth:** 4TB included (sufficient for 200 users)

**Why vsftpd:**
- Proven scalability: 4,000 concurrent users on 1GB RAM (benchmarked)
- Low memory footprint: 3-5MB per connection (vs ProFTPD's 50-80MB)
- Security-focused design (default deny, chroot jails, TLS required)
- Production-ready for 500+ users on this hardware

### Storage Architecture

**DigitalOcean Spaces:**
- Base: 250GB included at $5/month
- Additional: $0.02/GB for usage over 250GB
- Bandwidth: First 1TB free, then $0.01/GB
- S3-compatible API for integration

**FUSE Mount:**
- Use s3fs-fuse or goofys to mount Spaces as local filesystem
- Allows vsftpd to serve files directly from object storage
- Automatic scaling without manual intervention

**24-Hour Cleanup:**
- Cron job runs hourly: `find /ftp/* -type f -mtime +1 -delete`
- Configurable per-user if needed for premium tiers
- Database tracking for audit logs

---

## Financial Model

### Monthly Fixed Costs

| Item | Cost |
|------|------|
| DigitalOcean Droplet (2vCPU/4GB) | $24 |
| DigitalOcean Spaces (250GB base) | $5 |
| Domain + SSL (amortized) | $2 |
| Monitoring (Uptime Robot Pro) | $5 |
| Backup Storage (weekly snapshots) | $1 |
| **Total Fixed** | **$37** |

### Variable Costs (Per User/Month)

**Storage:** $5.62/user
- 256GB allocation × $0.02/GB = $5.12
- Bandwidth estimate: $0.50/user (50GB transfer @ $0.01/GB)

### Revenue Model at $14.99/month

| Users | Revenue | Fixed | Variable | Total Cost | Profit | Margin |
|-------|---------|-------|----------|------------|--------|--------|
| 7 | $105 | $37 | $39 | $76 | $29 | 27% |
| 50 | $750 | $37 | $281 | $318 | $432 | 58% |
| 100 | $1,499 | $37 | $562 | $599 | $900 | 60% |
| **200** | **$2,998** | **$37** | **$1,124** | **$1,161** | **$1,837** | **61%** |
| 500 | $7,495 | $37 | $2,810 | $2,847 | $4,648 | 62% |

### Break-Even Analysis

**Minimum subscribers needed:** 7 users
- Revenue: $105/month
- Costs: $76/month
- Profit: $29/month (27% margin)

**Sustainable threshold:** 50 users
- Revenue: $750/month
- Costs: $318/month
- Profit: $432/month (58% margin)

**Target scale:** 200 users
- Annual revenue: $35,976
- Annual profit: $22,044
- Infrastructure can scale to 500+ users without upgrades

---

## Competitive Analysis

### Market Positioning

| Service | Price | Storage | FTP Access | Auto-Cleanup |
|---------|-------|---------|------------|--------------|
| **Our Service** | $14.99/mo | 256GB | Yes (FTPS) | 24 hours |
| Dropbox | $11.99/mo | 2TB | No | Manual |
| iCloud+ | $9.99/mo | 2TB | No | Manual |
| Google Drive | $9.99/mo | 2TB | No | Manual |
| Dedicated FTP Hosting | $20-50/mo | 100-500GB | Yes | Manual |
| AWS Transfer Family | ~$216/mo | Pay-per-GB | Yes | Manual |

### Value Proposition

**Unique advantages:**
1. **Seamless integration** with FTPDownloader app (auto-configuration)
2. **Zero setup** - automatic provisioning after purchase
3. **Auto-cleanup** - files disappear after 24 hours (privacy + compliance)
4. **No technical knowledge required** - works out of the box
5. **Fair pricing** - competitive with consumer cloud storage but with FTP access

**Target customer:** Small businesses and professionals who need temporary FTP storage for:
- Client file delivery (photographers, designers, agencies)
- Automated workflows (data ingestion, backups)
- Testing and development
- Temporary file staging

---

## Security Architecture

### User Provisioning Flow

```
1. User purchases subscription in FTPDownloader app
2. App validates receipt with Apple StoreKit
3. App sends receipt to backend API (HTTPS)
4. Backend validates receipt with Apple servers
5. Backend creates virtual FTP user in PostgreSQL
6. Backend generates random password (20+ chars)
7. Backend returns FTP credentials to app
8. App auto-configures FTP connection
9. User starts downloading immediately
```

### Security Measures

**Network Security:**
- FTPS only (TLS 1.2+) - no plain FTP
- Force encryption: `require_ssl_reuse=YES`
- DDoS protection via DigitalOcean Cloud Firewalls
- Rate limiting: fail2ban with progressive bans
- Geographic restrictions if needed

**Authentication:**
- Virtual users only (no system accounts)
- PostgreSQL-backed credentials
- PAM integration for vsftpd
- Password complexity requirements (enforced by API)
- Optional 2FA for admin interface

**File System Security:**
- Chroot jails per user: `/ftp/users/{username}/`
- Read/write/delete within own directory only
- No cross-user file access
- Automatic cleanup prevents long-term data exposure
- Weekly snapshots for disaster recovery (admin only)

**API Security:**
- HTTPS only (Let's Encrypt SSL)
- JWT authentication for app-to-API communication
- Rate limiting: 10 requests/minute per IP
- Apple receipt validation as authorization proof
- Logging all provisioning events

**Compliance:**
- GDPR: 24-hour retention = minimal data exposure
- Right to deletion: automatic + manual API endpoint
- Encryption at rest: DigitalOcean Spaces default
- Encryption in transit: FTPS required
- Audit logs: PostgreSQL tracking all access

---

## Implementation Plan

### Phase 1: Infrastructure Setup (Week 1-2)

**Week 1:**
- [ ] Provision DigitalOcean droplet (2vCPU/4GB)
- [ ] Install Ubuntu 22.04 LTS
- [ ] Install vsftpd + PostgreSQL
- [ ] Configure s3fs-fuse for Spaces mounting
- [ ] Set up SSL certificates (Let's Encrypt)
- [ ] Configure basic firewall rules

**Week 2:**
- [ ] Configure vsftpd for virtual users (PAM + PostgreSQL)
- [ ] Set up chroot jails per user
- [ ] Configure FTPS with TLS 1.2+
- [ ] Implement 24-hour cleanup cron job
- [ ] Set up monitoring (Uptime Robot + system metrics)
- [ ] Create admin scripts for user management

### Phase 2: Backend API Development (Week 2-3)

**API Endpoints:**
```
POST /api/v1/provision
- Accepts: Apple receipt + app bundle ID
- Returns: FTP credentials (username/password/host/port)
- Error handling: invalid receipt, duplicate user, quota exceeded

DELETE /api/v1/deprovision
- Accepts: Apple receipt + username
- Returns: Success/failure
- Cleanup: Remove user from DB + delete files

GET /api/v1/status
- Accepts: Username (authenticated)
- Returns: Storage used, files count, last access
```

**Tech Stack:**
- Node.js (Express) or Python (FastAPI)
- PostgreSQL client library
- Apple StoreKit receipt validation SDK
- JWT for session management
- Rate limiting middleware

### Phase 3: App Integration (Week 4-5)

**FTPDownloader Changes:**

1. **Add StoreKit Product:**
   ```swift
   // Product ID: com.roningroupinc.FTPDownloader.CloudFTP
   // Type: Auto-renewable subscription
   // Price: $14.99/month
   ```

2. **Purchase Flow UI:**
   - New "Cloud FTP" tab in main window
   - Purchase button + subscription status
   - Display FTP credentials after purchase
   - Auto-configure FTP connection

3. **Backend Communication:**
   - Send receipt to provisioning API
   - Handle success/error responses
   - Store credentials securely in Keychain
   - Auto-create FTPConfig for cloud server

4. **Subscription Management:**
   - Display active/expired status
   - Handle renewal/cancellation
   - Show storage usage stats (from API)
   - Deprovision on cancellation

### Phase 4: Testing & Launch (Week 5-6)

**Beta Testing:**
- [ ] Internal testing with 5-10 test accounts
- [ ] Load testing: simulate 50 concurrent users
- [ ] Security audit: penetration testing
- [ ] Receipt validation edge cases
- [ ] Subscription renewal/cancellation flows

**Soft Launch:**
- [ ] Release to existing users (opt-in beta)
- [ ] Monitor for 2 weeks with free trial
- [ ] Collect feedback on UX and performance
- [ ] Fix critical bugs before public launch

**Public Launch:**
- [ ] App Store update with Cloud FTP feature
- [ ] Marketing materials (website, blog post)
- [ ] Support documentation
- [ ] Monitor signup rate and conversion

---

## Scalability Plan

### Current Architecture (200 users)

**Droplet:** 2 vCPU / 4GB RAM
**Capacity:** 500+ concurrent connections
**Bandwidth:** 4TB/month included
**Storage:** 256GB × 200 = 51.2TB (Spaces scales automatically)

### Growth Thresholds

**300 users:** No changes needed (within capacity)

**500 users:**
- Upgrade droplet to 4 vCPU / 8GB ($48/month)
- Still 60%+ profit margin
- Storage scales automatically

**1,000 users:**
- Load balancer + 2× droplets ($96/month total)
- DigitalOcean Spaces CDN for faster transfers
- Managed PostgreSQL database ($15/month)
- Total fixed costs: ~$120/month
- Revenue: $14,990/month
- Profit: $9,000+/month (60% margin maintained)

**10,000 users (aspirational):**
- Kubernetes cluster (3 nodes)
- Multiple geographic regions
- Dedicated support team
- Custom infrastructure (~$1,500/month)
- Revenue: $149,900/month
- Profit: $90,000+/month

---

## Risk Analysis

### Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Server downtime | High | 99.9% uptime SLA, monitoring, auto-restart |
| Data loss | Critical | Daily backups, object storage redundancy |
| DDoS attack | Medium | DigitalOcean DDoS protection, rate limiting |
| Storage overflow | Medium | Per-user quotas, 24-hour cleanup, alerts |
| vsftpd vulnerability | Medium | Auto-updates, security monitoring, fail2ban |

### Business Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Low adoption (<50 users) | High | Free trial period, marketing, user testimonials |
| High churn rate | Medium | Excellent UX, reliable service, support |
| Apple rejection | Critical | Follow App Store guidelines, clear ToS |
| Competitor undercuts price | Low | Value-add with app integration, auto-config |
| Costs exceed estimates | Medium | Conservative estimates, buffer in pricing |

### Regulatory Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| GDPR compliance | High | 24-hour retention, data deletion API, ToS |
| DMCA takedown | Medium | Abuse reporting, user ToS, quick response |
| Export controls (encryption) | Low | Standard FTPS (widely permitted) |
| Data breach notification | High | Encryption, logging, incident response plan |

---

## Marketing Strategy

### Target Audience

**Primary:**
- Photographers (deliver RAW files to clients)
- Designers (receive assets from collaborators)
- Video editors (temporary storage for renders)
- Developers (CI/CD pipeline integration)

**Secondary:**
- Small businesses (invoice/document delivery)
- Consultants (client data exchange)
- Researchers (data collection workflows)

### Messaging

**Headline:** "Your FTP Server in the Cloud - Zero Setup, Zero Hassle"

**Key benefits:**
- ✅ Instant setup (automatic after purchase)
- ✅ Secure FTPS encryption
- ✅ Auto-cleanup after 24 hours
- ✅ 256GB storage included
- ✅ Works seamlessly with FTPDownloader

**Call to action:** "Start your free 7-day trial"

### Channels

1. **In-app promotion**
   - Banner in FTPDownloader main window
   - Tooltip on first launch
   - Feature spotlight after 3rd configuration created

2. **Website**
   - Landing page: ftpdownloader.com/cloud
   - Pricing comparison table
   - Customer testimonials
   - Demo video (1-2 minutes)

3. **Content marketing**
   - Blog post: "Why We Built a Cloud FTP Service"
   - Tutorial: "Automate File Delivery with Cloud FTP"
   - Case study: "How [Customer] Saved 10 Hours/Week"

4. **Social proof**
   - Reddit (r/photography, r/webdev, r/smallbusiness)
   - ProductHunt launch
   - Twitter/X announcements
   - YouTube tutorial videos

---

## Support & Operations

### Customer Support

**Tier 1: Self-Service**
- FAQ page (setup, troubleshooting, billing)
- Video tutorials (YouTube playlist)
- In-app help tooltips

**Tier 2: Email Support**
- support@ftpdownloader.com
- 24-hour response time (business days)
- Ticketing system (Zendesk or Help Scout)

**Tier 3: Priority Support (future)**
- Premium tier at $29.99/month
- 4-hour response time
- Phone support
- Dedicated account manager at 100+ users

### Operational Tasks

**Daily:**
- Monitor server health (automated alerts)
- Check error logs for issues
- Respond to support tickets

**Weekly:**
- Review usage metrics (users, storage, bandwidth)
- Database backups verification
- Security log review

**Monthly:**
- Financial reconciliation (revenue vs. costs)
- Infrastructure scaling assessment
- Feature requests prioritization
- Churn analysis and outreach

---

## Success Metrics

### Key Performance Indicators (KPIs)

**Financial:**
- Monthly Recurring Revenue (MRR): Target $2,998 by month 6
- Customer Acquisition Cost (CAC): Target <$10 (organic growth)
- Lifetime Value (LTV): Target $180+ (12+ month retention)
- Churn rate: Target <5%/month

**Technical:**
- Uptime: 99.9%+ (max 43 minutes downtime/month)
- API response time: <200ms (p95)
- FTP transfer speed: >5MB/s average
- Error rate: <0.1% of requests

**Growth:**
- New subscribers/month: Target 20-30 (organic)
- Trial-to-paid conversion: Target 30%+
- User satisfaction (NPS): Target 50+
- Support ticket volume: <5% of users/month

### Milestones

**Month 1:** 10 beta users (free trial)
**Month 3:** 50 paying users ($750 MRR) - break-even
**Month 6:** 100 paying users ($1,499 MRR)
**Month 12:** 200 paying users ($2,998 MRR) - target achieved
**Year 2:** 500 paying users ($7,495 MRR) - scale infrastructure

---

## Next Steps

### Immediate Actions (Pre-Development)

1. **Validate demand**
   - Survey existing FTPDownloader users
   - Gauge interest via email/in-app poll
   - Target: 20+ expressions of interest

2. **Finalize pricing**
   - Confirm $14.99/month is acceptable
   - Consider tiered pricing (128GB/$9.99, 256GB/$14.99, 512GB/$24.99)
   - Decide on free trial length (7 vs. 14 days)

3. **Legal prep**
   - Draft Terms of Service
   - Draft Privacy Policy (GDPR-compliant)
   - Acceptable Use Policy (prevent abuse)
   - Consult attorney if needed

4. **App Store approval research**
   - Review similar apps with subscriptions
   - Ensure compliance with 3.1.1 (In-App Purchase)
   - Prepare review notes for Apple

### Development Kickoff (Week 1)

- [ ] Provision infrastructure (DigitalOcean account)
- [ ] Set up project management (Trello/Linear/GitHub Projects)
- [ ] Create development timeline (Gantt chart)
- [ ] Assign tasks if working with team
- [ ] Begin Phase 1 implementation

---

## Appendix

### vsftpd Configuration Snippet

```bash
# /etc/vsftpd.conf
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
virtual_use_local_privs=YES
guest_enable=YES
user_sub_token=$USER
local_root=/ftp/users/$USER
chroot_local_user=YES
hide_ids=YES

# Security
ssl_enable=YES
require_ssl_reuse=YES
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1_2=YES
rsa_cert_file=/etc/ssl/certs/vsftpd.pem
rsa_private_key_file=/etc/ssl/private/vsftpd.key

# PAM authentication (PostgreSQL-backed)
pam_service_name=vsftpd_virtual
guest_username=ftpuser

# Performance
max_clients=500
max_per_ip=5
```

### PostgreSQL Virtual User Schema

```sql
CREATE TABLE ftp_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL, -- bcrypt hash
    email VARCHAR(255),
    apple_receipt_id VARCHAR(255) UNIQUE,
    created_at TIMESTAMP DEFAULT NOW(),
    last_login TIMESTAMP,
    storage_quota BIGINT DEFAULT 274877906944, -- 256GB in bytes
    storage_used BIGINT DEFAULT 0,
    status VARCHAR(20) DEFAULT 'active', -- active, suspended, cancelled
    subscription_expires_at TIMESTAMP
);

CREATE TABLE access_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES ftp_users(id),
    action VARCHAR(50), -- login, upload, download, delete
    ip_address INET,
    timestamp TIMESTAMP DEFAULT NOW(),
    file_path TEXT,
    file_size BIGINT
);
```

### Cleanup Cron Job

```bash
#!/bin/bash
# /usr/local/bin/ftp_cleanup.sh
# Runs hourly via cron: 0 * * * * /usr/local/bin/ftp_cleanup.sh

LOG_FILE="/var/log/ftp_cleanup.log"
FTP_ROOT="/ftp/users"
RETENTION_HOURS=24

echo "[$(date)] Starting FTP cleanup..." >> "$LOG_FILE"

# Find and delete files older than 24 hours
find "$FTP_ROOT" -type f -mmin +$((RETENTION_HOURS * 60)) -exec rm -f {} \; -print >> "$LOG_FILE" 2>&1

# Update database with current storage usage
for USER_DIR in "$FTP_ROOT"/*; do
    if [ -d "$USER_DIR" ]; then
        USERNAME=$(basename "$USER_DIR")
        USAGE=$(du -sb "$USER_DIR" | cut -f1)
        psql -U ftpuser -d ftpdb -c "UPDATE ftp_users SET storage_used = $USAGE WHERE username = '$USERNAME';" >> "$LOG_FILE" 2>&1
    fi
done

echo "[$(date)] Cleanup complete." >> "$LOG_FILE"
```

---

## Document Version

**Version:** 1.0
**Date:** 2025-01-14
**Author:** FTPDownloader Development Team
**Status:** Planning Phase
**Next Review:** After user demand validation
