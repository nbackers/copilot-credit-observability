# Re-capturing the endpoints

These are private endpoints. If a call starts returning `404`, the path has moved and you need to
recapture it from the admin centre. This takes about five minutes and needs no app registration.

## Capture

1. Open the [Power Platform admin centre](https://admin.powerplatform.microsoft.com/).
2. Go to **Licensing → Copilot Studio**.
3. Press **F12** and select the **Network** tab.
4. Filter for `licensing.powerplatform` (or `entitlementConsumptions`, `MCSMessages`, `resources`).
5. Refresh, then click through **Summary**, **Copilot credit capacity**, **Environments**, and an
   individual environment row - each view issues a different request.
6. Select the request you want and record:
- full URL including query string
- HTTP method
- the `Authorization` header's **audience** (decode the token at [jwt.ms](https://jwt.ms) and read
     the `aud` claim - this is the detail most people get wrong)
- response JSON shape

## Replay

Right-click the request → **Copy → Copy as PowerShell**, then paste it into a terminal. The copied
command already carries the correct URL, audience and headers.

```powershell
# Save the response to inspect the schema
$result = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
$result | ConvertTo-Json -Depth 50 | Set-Content .\capture.json
code .\capture.json
```

Then work out where the collection lives - the two endpoints in this repo differ:

```powershell
$result.PSObject.Properties.Name     # top-level properties
$result.value    | Select-Object -First 1 | Format-List *
$result.resources| Select-Object -First 1 | Format-List *
$result[0]       | Format-List *     # array-wrapped responses
```

## Token safety

The bearer token in a copied request is a live credential.
- Never paste it into a website, including API documentation sites that offer a "try it" console.
- Don't commit it, and clear it from terminal history afterwards.
- It expires within the hour - for anything repeatable use `az account get-access-token` instead of
  a captured token.

## Please contribute what you find

If an endpoint has moved, open an issue using the **Endpoint change** template with the old and new
paths. Redact your tenant ID and any GUIDs.
