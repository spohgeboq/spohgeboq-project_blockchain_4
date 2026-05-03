# Monitoring Plan — DAO Governance System

## 1. Critical Events to Monitor

### 1.1 Governor Events

| Event | Signature | Why Monitor |
|-------|-----------|-------------|
| ProposalCreated | `ProposalCreated(uint256 proposalId, address proposer, ...)` | Track all new proposals. Alert on unexpected proposers or suspicious target contracts. |
| VoteCast | `VoteCast(address voter, uint256 proposalId, uint8 support, uint256 weight, string reason)` | Monitor voting activity. Detect large single-vote swings or last-minute voting. |
| ProposalQueued | `ProposalQueued(uint256 proposalId, uint256 eta)` | A proposal passed and is queued for execution. This is the last chance to react before execution. |
| ProposalExecuted | `ProposalExecuted(uint256 proposalId)` | Confirm successful execution. Verify state changes match expectations. |
| ProposalCanceled | `ProposalCanceled(uint256 proposalId)` | Investigate why a proposal was canceled. |

### 1.2 Timelock Events

| Event | Signature | Why Monitor |
|-------|-----------|-------------|
| CallScheduled | `CallScheduled(bytes32 id, ...)` | A governance action is scheduled. Verify the target and calldata match the proposal. |
| CallExecuted | `CallExecuted(bytes32 id, ...)` | Confirm execution completed. |
| MinDelayChange | `MinDelayChange(uint256 oldDuration, uint256 newDuration)` | CRITICAL: If the Timelock delay is reduced, the security window shrinks. |

### 1.3 Token Events

| Event | Signature | Why Monitor |
|-------|-----------|-------------|
| Transfer | `Transfer(address from, address to, uint256 value)` | Track large token movements that could affect governance power. |
| DelegateChanged | `DelegateChanged(address delegator, address fromDelegate, address toDelegate)` | Monitor delegation changes. Sudden mass delegation to a single address is suspicious. |
| DelegateVotesChanged | `DelegateVotesChanged(address delegate, uint256 previousVotes, uint256 newVotes)` | Track voting power concentration. Alert if any single address exceeds 25% of total voting power. |

### 1.4 Treasury Events

| Event | Signature | Why Monitor |
|-------|-----------|-------------|
| EtherReceived | `EtherReceived(address sender, uint256 amount)` | Track incoming funds. |
| EtherTransferred | `EtherTransferred(address to, uint256 amount)` | CRITICAL: Any outgoing ETH. Verify it matches an executed governance proposal. |
| TokenTransferred | `TokenTransferred(address token, address to, uint256 amount)` | CRITICAL: Any outgoing tokens. Verify it matches an executed governance proposal. |

### 1.5 Vesting Events

| Event | Signature | Why Monitor |
|-------|-----------|-------------|
| TokensReleased | `TokensReleased(address beneficiary, uint256 amount)` | Track vesting releases. Verify amounts match the expected linear schedule. |

---

## 2. Key Metrics to Track

### 2.1 Governance Health

| Metric | How to Calculate | Alert Threshold |
|--------|-----------------|-----------------|
| Voter Turnout | Total votes cast / Total delegated supply | Alert if < 5% on any proposal |
| Proposal Frequency | Count of ProposalCreated events per week | Alert if > 10 per week (spam) |
| Time to Quorum | Blocks from voting start to quorum reached | Informational |
| Proposal Success Rate | Succeeded proposals / Total proposals | Informational |
| Average Voting Period Usage | Block of last vote / Total voting period | Alert if most votes come in last 10% of period |

### 2.2 Token Concentration

| Metric | How to Calculate | Alert Threshold |
|--------|-----------------|-----------------|
| Top Holder Voting Power | `getVotes(address)` for top 10 delegates | Alert if any single address > 25% |
| Gini Coefficient | Distribution analysis of voting power | Alert if > 0.9 (extreme concentration) |
| Active Delegates | Count of addresses with > 0 delegated votes | Alert if < 10 |
| Token Velocity | Transfer volume / Total supply (7-day rolling) | Alert if > 50% (unusual trading) |

### 2.3 Treasury Health

| Metric | How to Calculate | Alert Threshold |
|--------|-----------------|-----------------|
| ETH Balance | `address(treasury).balance` | Alert if drops below minimum reserve |
| GTK Balance | `token.balanceOf(treasury)` | Alert on any decrease not matching a proposal |
| Outflow Rate | Sum of transfers per week | Alert if > 10% of balance per week |

---

## 3. Monitoring Implementation

### 3.1 Event Listener (ethers.js)

```javascript
const { ethers } = require("ethers");
const provider = new ethers.JsonRpcProvider(RPC_URL);

const governor = new ethers.Contract(GOVERNOR_ADDR, GOVERNOR_ABI, provider);
const token = new ethers.Contract(TOKEN_ADDR, TOKEN_ABI, provider);
const treasury = new ethers.Contract(TREASURY_ADDR, TREASURY_ABI, provider);

governor.on("ProposalCreated", (proposalId, proposer, ...args) => {
    console.log(`[PROPOSAL] New proposal ${proposalId} by ${proposer}`);
    sendAlert("New Governance Proposal", { proposalId, proposer });
});

governor.on("ProposalQueued", (proposalId, eta) => {
    console.log(`[QUEUED] Proposal ${proposalId} queued, ETA: ${new Date(Number(eta) * 1000)}`);
    sendAlert("Proposal Queued for Execution", { proposalId, eta });
});

treasury.on("EtherTransferred", (to, amount) => {
    console.log(`[TREASURY] ${ethers.formatEther(amount)} ETH sent to ${to}`);
    sendAlert("Treasury ETH Transfer", { to, amount: ethers.formatEther(amount) });
});

token.on("DelegateVotesChanged", (delegate, previousVotes, newVotes) => {
    const totalSupply = 1_000_000n * 10n ** 18n;
    const pct = (newVotes * 100n) / totalSupply;
    if (pct > 25n) {
        sendAlert("CRITICAL: Voting Power Concentration", {
            delegate,
            votingPower: `${pct}%`
        });
    }
});
```

### 3.2 Recommended Tools

| Tool | Purpose | Cost |
|------|---------|------|
| **OpenZeppelin Defender** | Automated monitoring, alerting, transaction execution | Free tier available |
| **Tenderly** | Transaction simulation, alerting, debugging | Free tier available |
| **The Graph** | Indexed event queries, historical data | Free for subgraph hosting |
| **Forta** | Real-time threat detection bots | Free for basic bots |
| **Custom Script** | Self-hosted ethers.js listener (shown above) | Hosting costs only |

### 3.3 Alert Channels

| Severity | Channel | Response Time |
|----------|---------|---------------|
| Critical (treasury drain, role change) | Telegram + Discord + PagerDuty | < 15 minutes |
| High (large delegation change, proposal queued) | Telegram + Discord | < 1 hour |
| Medium (new proposal, vote cast) | Discord | < 4 hours |
| Low (vesting release, incoming funds) | Dashboard log | Next business day |

---

## 4. Incident Response Plan

### 4.1 Malicious Proposal Detected

1. Alert fires on `ProposalCreated` with suspicious target/calldata
2. Analyze the proposal: what does it do? Who proposed it?
3. If confirmed malicious and still in voting period: rally community to vote Against
4. If proposal passes and is queued: guardian (if implemented) cancels the queued transaction
5. If executed: assess damage, pause affected contracts (if pausable), communicate to community

### 4.2 Voting Power Concentration

1. Alert fires on `DelegateVotesChanged` exceeding 25% threshold
2. Investigate: is this a known delegate or whale accumulation?
3. If suspicious: monitor for proposal creation from this address
4. Consider emergency governance response (e.g., proposal to increase quorum)

### 4.3 Treasury Anomaly

1. Alert fires on unexpected balance decrease
2. Cross-reference with executed proposals
3. If no matching proposal: investigate potential exploit
4. Communicate findings to community
