const TOKEN_ABI = [
    "function balanceOf(address) view returns (uint256)",
    "function getVotes(address) view returns (uint256)",
    "function delegates(address) view returns (address)",
    "function delegate(address)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)"
];

const GOVERNOR_ABI = [
    "function state(uint256 proposalId) view returns (uint8)",
    "function proposalVotes(uint256 proposalId) view returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)",
    "function proposalSnapshot(uint256 proposalId) view returns (uint256)",
    "function proposalDeadline(uint256 proposalId) view returns (uint256)",
    "function proposalProposer(uint256 proposalId) view returns (address)",
    "function hasVoted(uint256 proposalId, address account) view returns (bool)",
    "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
    "event ProposalCreated(uint256 proposalId, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 voteStart, uint256 voteEnd, string description)"
];

const STATE_NAMES = [
    "Pending", "Active", "Canceled", "Defeated",
    "Succeeded", "Queued", "Executed", "Expired"
];

const EXPECTED_CHAIN_ID = 31337n;
const ANVIL_CHAIN_ID_HEX = "0x7a69";
const ANVIL_NETWORK_PARAMS = {
    chainId: ANVIL_CHAIN_ID_HEX,
    chainName: "Anvil",
    nativeCurrency: {
        name: "Ethereum",
        symbol: "ETH",
        decimals: 18
    },
    rpcUrls: ["http://127.0.0.1:8545"],
    blockExplorerUrls: []
};
let TOKEN_ADDRESS   = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
let GOVERNOR_ADDRESS = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";

let provider, signer, tokenContract, governorContract, userAddress;

const $ = (id) => document.getElementById(id);

function showOverlay(msg) {
    $("overlayMsg").textContent = msg;
    $("overlay").style.display = "flex";
}
function hideOverlay() { $("overlay").style.display = "none"; }

function setStatus(elId, msg, isErr) {
    const el = $(elId);
    if (!el) return;
    el.textContent = msg;
    el.className = isErr ? "status-msg err" : "status-msg";
}

function getErrorMessage(e) {
    const message = e?.shortMessage || e?.reason || e?.message || "Transaction failed.";
    if (e?.code === 4001 || message.toLowerCase().includes("rejected")) {
        return "Transaction was rejected in MetaMask. Click the button again and press Confirm.";
    }
    return message;
}

function hasConnectedContracts() {
    return Boolean(provider && signer && tokenContract && governorContract && userAddress);
}

function requireConnected(statusId = "walletStatus") {
    if (hasConnectedContracts()) return true;
    setStatus(statusId, "Connect wallet on Anvil first.", true);
    document.getElementById("connectBtn").click();
    return false;
}

async function switchToAnvil() {
    try {
        await window.ethereum.request({
            method: "wallet_switchEthereumChain",
            params: [{ chainId: ANVIL_CHAIN_ID_HEX }]
        });
    } catch (switchError) {
        if (switchError.code !== 4902) throw switchError;

        await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [ANVIL_NETWORK_PARAMS]
        });
    }
}

async function ensureLocalDeployment() {
    const network = await provider.getNetwork();
    if (network.chainId !== EXPECTED_CHAIN_ID) {
        throw new Error(`Switch MetaMask to Anvil chain 31337. Current chain is ${network.chainId}.`);
    }

    const [tokenCode, governorCode] = await Promise.all([
        provider.getCode(TOKEN_ADDRESS),
        provider.getCode(GOVERNOR_ADDRESS)
    ]);

    if (tokenCode === "0x") {
        throw new Error(`GovernanceToken is not deployed at ${TOKEN_ADDRESS}. Restart Anvil and run the deploy script.`);
    }
    if (governorCode === "0x") {
        throw new Error(`MyGovernor is not deployed at ${GOVERNOR_ADDRESS}. Restart Anvil and run the deploy script.`);
    }
}

async function connectWallet() {
    if (!window.ethereum) { alert("MetaMask not found"); return; }

    provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);

    const initialNetwork = await provider.getNetwork();
    if (initialNetwork.chainId !== EXPECTED_CHAIN_ID) {
        setStatus("walletStatus", "MetaMask is switching to Anvil…");
        await switchToAnvil();
        provider = new ethers.BrowserProvider(window.ethereum);
    }

    signer   = await provider.getSigner();
    userAddress = await signer.getAddress();

    tokenContract    = new ethers.Contract(TOKEN_ADDRESS,   TOKEN_ABI,    signer);
    governorContract = new ethers.Contract(GOVERNOR_ADDRESS, GOVERNOR_ABI, signer);


    $("connectBtn").textContent = userAddress.slice(0, 6) + "…" + userAddress.slice(-4);
    $("connectBtn").disabled = true;


    $("app").style.display = "flex";


    $("panelAddress").value = userAddress;
    $("userAddress").textContent = userAddress;
    setStatus("walletStatus", "Connected. Reading DAO contracts…");

    try {
        await ensureLocalDeployment();
    } catch (e) {
        setStatus("walletStatus", e.message, true);
        return;
    }

    wirePanelVoteButtons();

    await refreshWallet();
}


async function refreshWallet() {
    try {
        const [balance, votes, delegate, decimals, symbol] = await Promise.all([
            tokenContract.balanceOf(userAddress),
            tokenContract.getVotes(userAddress),
            tokenContract.delegates(userAddress),
            tokenContract.decimals(),
            tokenContract.symbol()
        ]);

        const formattedVotes   = ethers.formatUnits(votes, decimals);
        const formattedBalance = ethers.formatUnits(balance, decimals);
        const delegateDisplay  = delegate === ethers.ZeroAddress
            ? "None (not delegated)"
            : delegate;


        $("userAddress").textContent  = userAddress;
        $("tokenBalance").textContent = formattedBalance + " " + symbol;
        $("votingPower").textContent  = formattedVotes   + " " + symbol;
        $("delegateAddr").textContent = delegateDisplay;


        $("panelVotingPower").value  = formattedVotes + " " + symbol;
        $("panelDelegate").value     = delegate === ethers.ZeroAddress
            ? "Not delegated"
            : delegate.slice(0, 6) + "…" + delegate.slice(-4);
        $("panelPowerDisplay").textContent = formattedVotes + " " + symbol;
        setStatus("walletStatus", "Wallet overview loaded.");

    } catch (e) {
        console.error("refreshWallet error:", e);
        setStatus("walletStatus", e.reason || e.shortMessage || e.message || "Could not read wallet overview.", true);
    }
}


function wirePanelVoteButtons() {
    document.querySelectorAll(".qv-btn").forEach(btn => {
        btn.addEventListener("click", async () => {
            const proposalId = $("panelProposalId").value.trim();
            if (!proposalId) {
                alert("Enter a Proposal ID in the panel first.");
                return;
            }
            const supportMap = { for: 1, against: 0, abstain: 2 };
            const support = supportMap[
                btn.classList.contains("for")      ? "for"     :
                btn.classList.contains("against")  ? "against" : "abstain"
            ];
            await castVoteFromPanel(proposalId, support);
        });
    });


    const submitBtn = document.querySelector(".btn-submit");
    if (submitBtn) {
        submitBtn.replaceWith(submitBtn.cloneNode(true)); 
        document.querySelector(".btn-submit").addEventListener("click", () => {
            const proposalId = $("panelProposalId").value.trim();
            if (!proposalId) { alert("Enter a Proposal ID."); return; }

            $("proposalsList").innerHTML = "";
            loadProposal(proposalId);
            document.getElementById("proposals-section").scrollIntoView({ behavior: "smooth" });
        });
    }
}

async function castVoteFromPanel(proposalId, support) {
    if (!requireConnected("walletStatus")) return;
    const labels = ["Against", "For", "Abstain"];
    try {
        showOverlay(`Casting vote: ${labels[support]}…`);
        const tx = await governorContract.castVote(proposalId, support);
        await tx.wait();
        hideOverlay();
        $("proposalsList").innerHTML = "";
        await loadProposal(proposalId);
        document.getElementById("proposals-section").scrollIntoView({ behavior: "smooth" });
    } catch (e) {
        hideOverlay();
        alert("Vote failed: " + getErrorMessage(e));
    }
}


async function delegateVotes(to) {
    if (!requireConnected("delegateStatus")) return;
    if (!ethers.isAddress(to)) {
        setStatus("delegateStatus", "Invalid delegate address.", true);
        return;
    }

    try {
        showOverlay("Delegating votes…");
        setStatus("delegateStatus", "Confirm delegation in MetaMask…");
        const tx = await tokenContract.delegate(to);
        setStatus("delegateStatus", "Tx sent: " + tx.hash);
        await tx.wait();
        setStatus("delegateStatus", "Delegation confirmed ✓");
        await refreshWallet();
    } catch (e) {
        setStatus("delegateStatus", getErrorMessage(e), true);
    } finally {
        hideOverlay();
    }
}


async function loadProposal(proposalId) {
    if (!requireConnected("walletStatus")) return;
    try {
        const [stateVal, votes, snapshot, deadline, proposer] = await Promise.all([
            governorContract.state(proposalId),
            governorContract.proposalVotes(proposalId),
            governorContract.proposalSnapshot(proposalId),
            governorContract.proposalDeadline(proposalId),
            governorContract.proposalProposer(proposalId)
        ]);

        const hasVoted = await governorContract.hasVoted(proposalId, userAddress);

        renderProposal({
            id:          proposalId,
            state:       Number(stateVal),
            against:     votes[0],
            forVotes:    votes[1],
            abstain:     votes[2],
            snapshot:    snapshot.toString(),
            deadline:    deadline.toString(),
            proposer,
            description: "Proposal #" + proposalId.toString().slice(0, 8) + "…",
            hasVoted
        });


        syncPanelVotesBar(votes[1], votes[0], votes[2]);

    } catch (e) {
        alert("Failed to load proposal: " + getErrorMessage(e));
    }
}


function syncPanelVotesBar(forVotes, against, abstain) {
    const total = forVotes + against + abstain;
    if (total === 0n) return;
    const pctFor     = Number((forVotes * 10000n) / total) / 100;
    const pctAgainst = Number((against  * 10000n) / total) / 100;
    const pctAbstain = Number((abstain  * 10000n) / total) / 100;

    const bar = document.querySelector(".payment-panel .votes-bar");
    if (!bar) return;
    bar.querySelector(".vb-for").style.width     = pctFor     + "%";
    bar.querySelector(".vb-against").style.width = pctAgainst + "%";
    bar.querySelector(".vb-abstain").style.width = pctAbstain + "%";

    const counts = document.querySelectorAll(".payment-panel .vc");
    if (counts[0]) counts[0].childNodes[1].textContent = ` ${pctFor.toFixed(1)}% For`;
    if (counts[1]) counts[1].childNodes[1].textContent = ` ${pctAgainst.toFixed(1)}% Against`;
    if (counts[2]) counts[2].childNodes[1].textContent = ` ${pctAbstain.toFixed(1)}% Abstain`;
}


async function scanProposals() {
    if (!requireConnected("walletStatus")) return;
    const from = $("fromBlock").value ? parseInt($("fromBlock").value) : 0;
    const to   = $("toBlock").value   ? parseInt($("toBlock").value)   : "latest";

    showOverlay("Scanning blocks for ProposalCreated events…");

    try {
        const filter = governorContract.filters.ProposalCreated();
        const events = await governorContract.queryFilter(filter, from, to);

        $("proposalsList").innerHTML = "";

        if (events.length === 0) {
            $("proposalsList").innerHTML =
                '<div class="proposal-card"><p style="color:var(--text-muted)">No proposals found in this block range.</p></div>';
            hideOverlay();
            return;
        }

        for (const ev of events) {
            await loadProposal(ev.args[0]);
        }
    } catch (e) {
        alert("Scan error: " + getErrorMessage(e));
    } finally {
        hideOverlay();
    }
}

function renderProposal(p) {
    const total      = p.forVotes + p.against + p.abstain;
    const pctFor     = total > 0n ? Number((p.forVotes * 10000n) / total) / 100 : 0;
    const pctAgainst = total > 0n ? Number((p.against  * 10000n) / total) / 100 : 0;
    const pctAbstain = total > 0n ? Number((p.abstain  * 10000n) / total) / 100 : 0;

    const card = document.createElement("div");
    card.className = "proposal-card";

    const canVote  = p.state === 1 && !p.hasVoted;
    const votedLabel = p.hasVoted
        ? '<span style="color:#27ff42; font-size:0.78rem; margin-left:8px;">✓ Voted</span>'
        : "";

    card.innerHTML = `
        <h3>
            ${p.description}
            <span class="state-badge state-${p.state}">${STATE_NAMES[p.state]}</span>
            ${votedLabel}
        </h3>
        <div class="proposal-meta">
            <span>ID: ${p.id.toString().slice(0, 12)}…</span>
            <span>Proposer: ${p.proposer.slice(0, 6)}…${p.proposer.slice(-4)}</span>
            <span>Snapshot: block ${p.snapshot}</span>
            <span>Deadline: block ${p.deadline}</span>
        </div>
        <div class="prop-votes-bar">
            <div class="pv-for"     style="width:${pctFor}%"></div>
            <div class="pv-against" style="width:${pctAgainst}%"></div>
            <div class="pv-abstain" style="width:${pctAbstain}%"></div>
            ${total === 0n ? '<div class="pv-abstain" style="width:100%"></div>' : ""}
        </div>
        <div style="font-size:0.75rem; color:var(--text-muted); display:flex; gap:16px; flex-wrap:wrap;">
            <span style="color:#27ff42;">For: ${ethers.formatEther(p.forVotes)}</span>
            <span style="color:#ef4444;">Against: ${ethers.formatEther(p.against)}</span>
            <span style="color:#475569;">Abstain: ${ethers.formatEther(p.abstain)}</span>
            ${total === 0n ? '<span>No votes yet</span>' : ""}
        </div>
        ${canVote ? `
        <div class="vote-btns">
            <button class="btn-action vote-for"     data-id="${p.id}" data-support="1">Vote For</button>
            <button class="btn-action vote-against" data-id="${p.id}" data-support="0">Vote Against</button>
            <button class="btn-action vote-abstain" data-id="${p.id}" data-support="2">Abstain</button>
        </div>` : ""}
    `;

    card.querySelectorAll(".vote-btns button").forEach(btn => {
        btn.addEventListener("click", () =>
            castVote(btn.dataset.id, parseInt(btn.dataset.support))
        );
    });

    $("proposalsList").appendChild(card);
}


async function castVote(proposalId, support) {
    if (!requireConnected("walletStatus")) return;
    const labels = ["Against", "For", "Abstain"];
    try {
        showOverlay(`Casting vote: ${labels[support]}…`);
        const tx = await governorContract.castVote(proposalId, support);
        await tx.wait();
        hideOverlay();
        $("proposalsList").innerHTML = "";
        await loadProposal(proposalId);
    } catch (e) {
        hideOverlay();
        alert("Vote failed: " + getErrorMessage(e));
    }
}

$("connectBtn").addEventListener("click", connectWallet);

$("delegateSelfBtn").addEventListener("click", () => {
    if (!requireConnected("delegateStatus")) return;
    delegateVotes(userAddress);
});

$("delegateBtn").addEventListener("click", () => {
    if (!requireConnected("delegateStatus")) return;
    const addr = $("delegateInput").value.trim() || userAddress;
    if (!ethers.isAddress(addr)) {
        setStatus("delegateStatus", "Invalid address", true);
        return;
    }
    delegateVotes(addr);
});

$("loadProposalBtn").addEventListener("click", () => {
    const id = $("proposalIdInput").value.trim();
    if (!id) return;
    $("proposalsList").innerHTML = "";
    loadProposal(id);
});

$("scanBtn").addEventListener("click", scanProposals);


$("panelProposalId").addEventListener("input", (e) => {
    $("proposalIdInput").value = e.target.value;
});

if (window.ethereum) {
    window.ethereum.on("accountsChanged", () => location.reload());
    window.ethereum.on("chainChanged",    () => location.reload());
}
