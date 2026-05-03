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

let TOKEN_ADDRESS = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
let GOVERNOR_ADDRESS = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";

let provider, signer, tokenContract, governorContract, userAddress;

const $ = (id) => document.getElementById(id);

function showOverlay(msg) { $("overlayMsg").textContent = msg; $("overlay").style.display = "flex"; }
function hideOverlay() { $("overlay").style.display = "none"; }

function setStatus(elId, msg, isErr) {
    const el = $(elId);
    el.textContent = msg;
    el.className = isErr ? "status err" : "status";
}

async function connectWallet() {
    if (!window.ethereum) { alert("MetaMask not found"); return; }

    provider = new ethers.BrowserProvider(window.ethereum);
    signer = await provider.getSigner();
    userAddress = await signer.getAddress();

    tokenContract = new ethers.Contract(TOKEN_ADDRESS, TOKEN_ABI, signer);
    governorContract = new ethers.Contract(GOVERNOR_ADDRESS, GOVERNOR_ABI, signer);

    $("connectBtn").textContent = userAddress.slice(0, 6) + "…" + userAddress.slice(-4);
    $("connectBtn").disabled = true;
    $("app").style.display = "flex";

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

        $("userAddress").textContent = userAddress;
        $("tokenBalance").textContent = ethers.formatUnits(balance, decimals) + " " + symbol;
        $("votingPower").textContent = ethers.formatUnits(votes, decimals) + " " + symbol;
        $("delegateAddr").textContent = delegate === ethers.ZeroAddress ? "None (not delegated)" : delegate;
    } catch (e) {
        console.error("refreshWallet error:", e);
    }
}

async function delegateVotes(to) {
    try {
        showOverlay("Delegating votes…");
        const tx = await tokenContract.delegate(to);
        setStatus("delegateStatus", "Tx sent: " + tx.hash);
        await tx.wait();
        setStatus("delegateStatus", "Delegation confirmed ✓");
        await refreshWallet();
    } catch (e) {
        setStatus("delegateStatus", e.reason || e.message, true);
    } finally {
        hideOverlay();
    }
}

async function loadProposal(proposalId) {
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
            id: proposalId,
            state: Number(stateVal),
            against: votes[0],
            forVotes: votes[1],
            abstain: votes[2],
            snapshot: snapshot.toString(),
            deadline: deadline.toString(),
            proposer,
            description: "Proposal #" + proposalId.toString().slice(0, 8) + "…",
            hasVoted
        });
    } catch (e) {
        alert("Failed to load proposal: " + (e.reason || e.message));
    }
}

async function scanProposals() {
    const from = $("fromBlock").value ? parseInt($("fromBlock").value) : 0;
    const to = $("toBlock").value ? parseInt($("toBlock").value) : "latest";

    showOverlay("Scanning blocks for ProposalCreated events…");

    try {
        const filter = governorContract.filters.ProposalCreated();
        const events = await governorContract.queryFilter(filter, from, to);

        $("proposalsList").innerHTML = "";

        if (events.length === 0) {
            $("proposalsList").innerHTML = '<div class="proposal-card"><p>No proposals found in this block range.</p></div>';
            hideOverlay();
            return;
        }

        for (const ev of events) {
            const proposalId = ev.args[0];
            await loadProposal(proposalId);
        }
    } catch (e) {
        alert("Scan error: " + (e.reason || e.message));
    } finally {
        hideOverlay();
    }
}

function renderProposal(p) {
    const total = p.forVotes + p.against + p.abstain;
    const pctFor = total > 0n ? Number((p.forVotes * 10000n) / total) / 100 : 0;
    const pctAgainst = total > 0n ? Number((p.against * 10000n) / total) / 100 : 0;
    const pctAbstain = total > 0n ? Number((p.abstain * 10000n) / total) / 100 : 0;

    const card = document.createElement("div");
    card.className = "proposal-card";

    const canVote = p.state === 1 && !p.hasVoted;
    const votedLabel = p.hasVoted ? '<span style="color:#22c55e;">✓ You voted</span>' : "";

    card.innerHTML = `
        <h3>${p.description} <span class="state-badge state-${p.state}">${STATE_NAMES[p.state]}</span> ${votedLabel}</h3>
        <div class="proposal-meta">
            <span>ID: ${p.id.toString().slice(0, 12)}…</span>
            <span>Proposer: ${p.proposer.slice(0, 6)}…${p.proposer.slice(-4)}</span>
            <span>Snapshot: block ${p.snapshot}</span>
            <span>Deadline: block ${p.deadline}</span>
        </div>
        <div class="votes-bar">
            ${pctFor > 0 ? `<div class="bar-for" style="width:${pctFor}%">For ${pctFor.toFixed(1)}%</div>` : ""}
            ${pctAgainst > 0 ? `<div class="bar-against" style="width:${pctAgainst}%">Against ${pctAgainst.toFixed(1)}%</div>` : ""}
            ${pctAbstain > 0 ? `<div class="bar-abstain" style="width:${pctAbstain}%">Abstain ${pctAbstain.toFixed(1)}%</div>` : ""}
            ${total === 0n ? '<div class="bar-abstain" style="width:100%">No votes yet</div>' : ""}
        </div>
        <div style="font-size:0.8rem;color:#94a3b8;">
            For: ${ethers.formatEther(p.forVotes)} · Against: ${ethers.formatEther(p.against)} · Abstain: ${ethers.formatEther(p.abstain)}
        </div>
        ${canVote ? `
        <div class="vote-btns">
            <button class="vote-for" data-id="${p.id}" data-support="1">Vote For</button>
            <button class="vote-against" data-id="${p.id}" data-support="0">Vote Against</button>
            <button class="vote-abstain" data-id="${p.id}" data-support="2">Abstain</button>
        </div>` : ""}
    `;

    card.querySelectorAll(".vote-btns button").forEach(btn => {
        btn.addEventListener("click", () => castVote(btn.dataset.id, parseInt(btn.dataset.support)));
    });

    $("proposalsList").appendChild(card);
}

async function castVote(proposalId, support) {
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
        alert("Vote failed: " + (e.reason || e.message));
    }
}

$("connectBtn").addEventListener("click", connectWallet);

$("delegateSelfBtn").addEventListener("click", () => delegateVotes(userAddress));

$("delegateBtn").addEventListener("click", () => {
    const addr = $("delegateInput").value.trim();
    if (!ethers.isAddress(addr)) { setStatus("delegateStatus", "Invalid address", true); return; }
    delegateVotes(addr);
});

$("loadProposalBtn").addEventListener("click", () => {
    const id = $("proposalIdInput").value.trim();
    if (!id) return;
    $("proposalsList").innerHTML = "";
    loadProposal(id);
});

$("scanBtn").addEventListener("click", scanProposals);

if (window.ethereum) {
    window.ethereum.on("accountsChanged", () => location.reload());
    window.ethereum.on("chainChanged", () => location.reload());
}
