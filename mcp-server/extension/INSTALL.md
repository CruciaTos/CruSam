# Connect CruSam to Claude Desktop

This takes about 2 minutes. You need two files from Soham: `crusam.mcpb`
and this guide.

## Before you start

- A Windows computer with the **CruSam app** installed. **Open CruSam at
  least once** on this computer (with your own Windows account), so it
  creates its data file.
- **Claude Desktop**, signed in with your own Claude account. Update it to
  the latest version (menu → Help → Check for updates).

## Install

1. Double-click **`crusam.mcpb`**. Claude Desktop opens and shows an
   "Install CruSam" screen.
   *If nothing happens:* in Claude Desktop, go to **Settings → Extensions →
   Advanced settings → Install extension…** and pick `crusam.mcpb`.
2. Click **Install**. Claude may say the extension is not verified. That's
   expected, because it's a private extension made for CruSam.
3. On the settings screen:
   - **CruSam database:** leave it empty. It finds your CruSam data
     automatically.
   - **Read-only:** optional. Turn it on for your first try if you only want
     Claude to look, not change anything. You can turn it off later.
   - **Your email:** optional. It's saved as the creator of invoices Claude
     makes.
4. Make sure the CruSam extension is switched **on** (Settings →
   Extensions).
5. Start a **new chat**.

## Try it

- "Using CruSam, give me an overview."
- Attach a photo of a PO list: "Create an invoice in CruSam from this photo,
  client Diversey, date 2026-06-01."

Claude always shows you a preview of an invoice, with every row and the
totals, before saving. Nothing is saved until you say yes.

## Good to know

- **Your data stays local.** Everything stays on your computer. Only your
  conversation goes to Claude, as in any other chat.
- **Backups.** Before its first change in each chat session, the extension
  saves a copy of your data in a `mcp_backups` folder next to the CruSam
  data file.
- **App already open.** If the CruSam app is open, reopen the Invoices,
  Employees or Saved Salary screen to see what Claude changed.
- **Updating.** When Soham sends a newer `crusam.mcpb`, double-click it and
  install over the old one. Your settings stay.

## If something goes wrong

| What you see | What to do |
|---|---|
| "CruSam database not found" | Open the CruSam app once, then restart Claude Desktop. |
| Claude doesn't mention CruSam or its tools | Settings → Extensions: check CruSam is switched on, then start a new chat. |
| "The database is busy" | CruSam was saving at the same moment. Ask Claude to try again. |
| Anything else | Settings → Extensions → CruSam shows the error. Send Soham a screenshot. |
