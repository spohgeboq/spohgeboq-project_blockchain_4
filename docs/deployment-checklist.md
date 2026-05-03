# Deployment Checklist & Post-Deployment Verification

## 1. Pre-Deployment Checklist

| # | Step | Command | Status |
|---|------|---------|--------|
| 1 | Compile all contracts | `forge build` | |
| 2 | Run full test suite | `forge test -vvv` | |
| 3 | Run Slither analysis | `slither . --filter-paths "lib\|test\|script"` | |
| 4 | Set deployer private key | `export PRIVATE_KEY=0x...` | |
| 5 | Verify deployer has enough ETH | `cast balance $DEPLOYER --rpc-url $RPC_URL` | |
| 6 | Confirm target network RPC URL | `cast chain-id --rpc-url $RPC_URL` | |

## 2. Deployment Order

The deployment script (`script/DeployDAO.s.sol`) deploys contracts in the correct dependency order:

```
1. TimelockController  (no dependencies)
2. GovernanceToken     (depends on: Timelock address for treasury allocation)
3. MyGovernor          (depends on: Token + Timelock)
4. Treasury            (depends on: Timelock as owner)
5. Box                 (depends on: Timelock as owner)
6. TokenVesting        (depends on: Token address)
```

### Deployment Command

```bash
# Local (Anvil)
anvil --host 127.0.0.1 --port 8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
forge script script/DeployDAO.s.sol:DeployDAO \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast

# Testnet (Base Sepolia)
export PRIVATE_KEY=<your-deployer-key>
forge script script/DeployDAO.s.sol:DeployDAO \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --verify \
  --etherscan-api-key <BASESCAN_API_KEY>
```

## 3. Post-Deployment Verification Steps

After deployment, run the following checks to verify correct configuration:

### 3.1 Verify Roles & Permissions

```bash
RPC="http://127.0.0.1:8545"
TIMELOCK="<TimelockController address>"
GOVERNOR="<MyGovernor address>"
TOKEN="<GovernanceToken address>"
TREASURY="<Treasury address>"
BOX="<Box address>"

# Governor is the sole proposer on Timelock
cast call $TIMELOCK "hasRole(bytes32,address)(bool)" \
  $(cast call $TIMELOCK "PROPOSER_ROLE()(bytes32)" --rpc-url $RPC) \
  $GOVERNOR --rpc-url $RPC
# Expected: true

# Anyone can execute (address(0) has EXECUTOR_ROLE)
cast call $TIMELOCK "hasRole(bytes32,address)(bool)" \
  $(cast call $TIMELOCK "EXECUTOR_ROLE()(bytes32)" --rpc-url $RPC) \
  0x0000000000000000000000000000000000000000 --rpc-url $RPC
# Expected: true

# Deployer no longer has admin role
cast call $TIMELOCK "hasRole(bytes32,address)(bool)" \
  $(cast call $TIMELOCK "DEFAULT_ADMIN_ROLE()(bytes32)" --rpc-url $RPC) \
  <DEPLOYER_ADDRESS> --rpc-url $RPC
# Expected: false

# Treasury is owned by Timelock
cast call $TREASURY "owner()(address)" --rpc-url $RPC
# Expected: <TimelockController address>

# Box is owned by Timelock
cast call $BOX "owner()(address)" --rpc-url $RPC
# Expected: <TimelockController address>
```

### 3.2 Verify Governor Parameters

```bash
# Voting delay (expected: 7200 blocks ~ 1 day)
cast call $GOVERNOR "votingDelay()(uint256)" --rpc-url $RPC

# Voting period (expected: 50400 blocks ~ 1 week)
cast call $GOVERNOR "votingPeriod()(uint256)" --rpc-url $RPC

# Quorum numerator (expected: 4%)
cast call $GOVERNOR "quorumNumerator()(uint256)" --rpc-url $RPC

# Proposal threshold (expected: 1% of total supply = 10000 GTK)
cast call $GOVERNOR "proposalThreshold()(uint256)" --rpc-url $RPC
```

### 3.3 Verify Timelock Delay

```bash
# Timelock minimum delay (expected: 172800 seconds = 2 days)
cast call $TIMELOCK "getMinDelay()(uint256)" --rpc-url $RPC
```

### 3.4 Verify Token Distribution

```bash
# Total supply (expected: 1000000e18)
cast call $TOKEN "totalSupply()(uint256)" --rpc-url $RPC

# Team allocation in vesting contract (expected: 400000e18)
cast call $TOKEN "balanceOf(address)(uint256)" <VESTING_ADDRESS> --rpc-url $RPC

# Treasury allocation (expected: 300000e18)
cast call $TOKEN "balanceOf(address)(uint256)" $TIMELOCK --rpc-url $RPC

# Community allocation
cast call $TOKEN "balanceOf(address)(uint256)" <COMMUNITY_ADDRESS> --rpc-url $RPC

# Liquidity allocation
cast call $TOKEN "balanceOf(address)(uint256)" <LIQUIDITY_ADDRESS> --rpc-url $RPC
```

### 3.5 Verify Contract Source on Etherscan

```bash
forge verify-contract <TOKEN_ADDRESS> src/GovernanceToken.sol:GovernanceToken \
  --chain-id 84532 \
  --etherscan-api-key <API_KEY> \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address)" \
    <team> <treasury> <community> <liquidity>)
```

Repeat for all five contracts.

## 4. Verification Checklist

| # | Check | Expected Result | Verified |
|---|-------|-----------------|----------|
| 1 | Deployer has no admin role on Timelock | `false` | |
| 2 | Governor has PROPOSER_ROLE on Timelock | `true` | |
| 3 | address(0) has EXECUTOR_ROLE on Timelock | `true` | |
| 4 | Treasury.owner == Timelock | `true` | |
| 5 | Box.owner == Timelock | `true` | |
| 6 | Timelock delay == 172800 (2 days) | `true` | |
| 7 | Voting delay == 7200 blocks | `true` | |
| 8 | Voting period == 50400 blocks | `true` | |
| 9 | Quorum == 4% | `true` | |
| 10 | Total supply == 1,000,000 GTK | `true` | |
| 11 | Team tokens in vesting contract | 400,000 GTK | |
| 12 | Treasury tokens in Timelock | 300,000 GTK | |
| 13 | All contracts verified on Etherscan | Links | |
