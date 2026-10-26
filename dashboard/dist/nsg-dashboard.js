"use strict";

const refreshButton = document.getElementById("refresh");
const results = document.getElementById("results");
const statusMessage = document.getElementById("status");
const tableWrap = document.getElementById("table-wrap");
const rows = document.getElementById("findings");
const count = document.getElementById("count");
const retrieved = document.getElementById("retrieved");

function formatDate(value) {
  if (!value) return "Not available";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "Not available" : date.toLocaleString();
}

async function loadFindings() {
  refreshButton.disabled = true;
  results.setAttribute("aria-busy", "true");
  statusMessage.hidden = false;
  statusMessage.className = "";
  statusMessage.textContent = "Loading saved findings…";
  tableWrap.hidden = true;
  rows.replaceChildren();
  count.textContent = "—";
  retrieved.textContent = "Not yet loaded";
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 65000);

  try {
    const response = await fetch("/api/findings", {
      headers: { Accept: "application/json" },
      cache: "no-store",
      signal: controller.signal
    });
    if (!response.ok) throw new Error("Request failed");
    const data = await response.json();
    if (!Array.isArray(data.findings) || data.findings.some(finding =>
      !finding || typeof finding !== "object" ||
      !["nsg_name", "rule_name", "status", "last_checked"].every(
        key => typeof finding[key] === "string"
      )
    )) throw new Error("Unexpected response");

    count.textContent = String(data.findings.length);
    retrieved.textContent = new Date().toLocaleString();

    if (data.findings.length === 0) {
      statusMessage.textContent = "No saved unrestricted-source SSH findings. This is not a live scan.";
      return;
    }

    for (const finding of data.findings) {
      const row = document.createElement("tr");
      const values = [finding.nsg_name, finding.rule_name, finding.status, formatDate(finding.last_checked)];
      values.forEach((value, index) => {
        const cell = document.createElement("td");
        if (index === 2) {
          const badge = document.createElement("span");
          if (finding.status === "Risky") badge.className = "risk";
          badge.textContent = value;
          cell.appendChild(badge);
        } else {
          cell.textContent = value;
        }
        row.appendChild(cell);
      });
      rows.appendChild(row);
    }
    statusMessage.textContent = "Saved findings loaded. Dates are shown in your browser’s local time.";
    tableWrap.hidden = false;
  } catch (error) {
    statusMessage.className = "error";
    statusMessage.textContent = "Could not load findings. Check the backend connection and try Refresh findings. This does not mean there are no risks.";
    retrieved.textContent = "Request failed";
  } finally {
    clearTimeout(timeout);
    refreshButton.disabled = false;
    results.setAttribute("aria-busy", "false");
  }
}

refreshButton.addEventListener("click", loadFindings);
loadFindings();
