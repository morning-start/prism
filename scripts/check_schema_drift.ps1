param(
  [switch]$Strict,
  [switch]$SelfTest,
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$schemaPath = Join-Path $Root "schemas/lux-ir-v1.json"
$sourceRoot = Join-Path $Root "src/lux"
$schemaText = Get-Content -Raw -Encoding UTF8 $schemaPath
$schema = $schemaText | ConvertFrom-Json
$sourceFiles = Get-ChildItem -LiteralPath $sourceRoot -Filter "*.mbt" -File | Where-Object { $_.Name -notmatch "_(test|wbtest)\.mbt$" }
$source = ($sourceFiles | ForEach-Object { Get-Content -Raw -Encoding UTF8 $_.FullName }) -join "`n"

function New-Issue([string]$Category, [string]$Location, [string]$Expected, [string]$Actual, [string]$Message) {
  [pscustomobject]@{ Category=$Category; Location=$Location; Expected=$Expected; Actual=$Actual; Message=$Message }
}

function Get-SourceStructs([string]$Text) {
  $result = @{}
  foreach ($m in [regex]::Matches($Text, "(?ms)(?:pub\s+)?struct\s+(\w+)\s*\{(.*?)\}")) {
    $fields = [regex]::Matches($m.Groups[2].Value, "(?m)^\s*([a-zA-Z_]\w*)\s*:") | ForEach-Object { $_.Groups[1].Value }
    $result[$m.Groups[1].Value] = @($fields)
  }
  return $result
}

function Get-SourceEnums([string]$Text) {
  $result = @{}
  foreach ($m in [regex]::Matches($Text, "(?ms)(?:pub\s*\([^)]*\)\s+)?enum\s+(\w+)\s*\{(.*?)\}")) {
    $variants = [regex]::Matches($m.Groups[2].Value, "(?m)^\s*([A-Z][A-Za-z0-9_]*)\b") | ForEach-Object { $_.Groups[1].Value }
    $result[$m.Groups[1].Value] = @($variants)
  }
  return $result
}

function Convert-ToWireName([string]$Name) {
  if ($Name -eq "MCP") { return "mcp" }
  return ([regex]::Replace($Name, "(?<!^)(?=[A-Z])", "_")).ToLowerInvariant()
}

function Get-SchemaEnumValues($Schema) {
  $result = @{}
  foreach ($property in $Schema.definitions.psobject.Properties) {
    if ($null -ne $property.Value.enum) { $result[$property.Name] = @($property.Value.enum) }
  }
  return $result
}

function Get-RequiredFields($Schema) {
  $result = @{}
  foreach ($property in $Schema.definitions.psobject.Properties) {
    if ($null -ne $property.Value.required) { $result[$property.Name] = @($property.Value.required) }
  }
  return $result
}

function Get-SchemaVersions([string]$Text) {
  @([regex]::Matches($Text, '"schema_version"\s*:\s*\{[^}]*?"const"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}

function Get-SourceVersions([string]$Text) {
  @([regex]::Matches($Text, 'schema_version\s*:\s*"([^"]+)"|schema_version\s*=\s*"([^"]+)"') | ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } } | Select-Object -Unique)
}

function Get-StreamEvents([string]$SchemaText, [string]$SourceText) {
  $schemaPart = ($SchemaText | ConvertFrom-Json).definitions.LucentStreamEvent | ConvertTo-Json -Depth 30 -Compress
  $expected = @([regex]::Matches($schemaPart, '"const":"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Sort-Object)
  $actual = @([regex]::Matches($SourceText, '"event"\s*:\s*Json::string\("([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Sort-Object)
  @{ Expected=$expected; Actual=$actual }
}

# === adapter 输出侧检查（G6） ===
# 预期输出字段集来源：
#   openai   -> .agent-workplace/research/api-protocol-converter/references/chat-completions-spec.md
#   messages -> .agent-workplace/research/api-protocol-converter/references/messages-spec.md
#   responses-> .agent-workplace/research/api-protocol-converter/references/responses-spec.md
#   gemini   -> .agent-workplace/research/api-protocol-converter/references/three-protocol-guide.md
# 规则：adapter request_encode 实际输出的 JSON 字段名必须是目标端点协议允许的字段；
#       输出协议字段集之外的字段 = 漂移（拼写错误 / 未注册字段 / schema 失配）。

function Get-AdapterExpectedFields([string]$Adapter) {
  $sets = @{
    "openai" = @("model","messages","max_tokens","temperature","top_p","stop","stream","store",
      "response_format","tool_choice","tools","reasoning_effort","role","content","name",
      "tool_call_id","tool_calls","refusal","type","text","image_url","url","function","id",
      "arguments","description","parameters","strict","parallel_tool_calls","schema","json_schema")
    "messages" = @("model","system","messages","max_tokens","temperature","top_p","top_k",
      "stop_sequences","stream","metadata","tools","tool_choice","thinking","output_config",
      "type","text","signature","thinking","id","name","input","is_error","tool_use_id",
      "source","media_type","data","url","input_schema","description","budget_tokens","effort","format",
      "schema","disable_parallel_tool_use","role","content")
    "responses" = @("model","instructions","max_output_tokens","temperature","top_p","stream",
      "store","tools","reasoning","parallel_tool_calls","type","role","content","id","call_id",
      "name","arguments","output","status","summary","text","image_url","file_data","description",
      "parameters","schema","strict","format","effort","input")
    "gemini" = @("model","systemInstruction","contents","tools","toolConfig","generationConfig",
      "role","parts","text","thought","thoughtSignature","functionCall","functionResponse",
      "fileData","fileUri","mimeType","name","args","response","content","functionDeclarations",
      "description","parameters","functionCallingConfig","mode","temperature","topP","topK",
      "maxOutputTokens","stopSequences","responseMimeType","responseSchema","candidateCount",
      "thinkingConfig","thinkingBudget","includeThoughts","thinkingLevel","inlineData","data")
  }
  $sets[$Adapter]
}

function Get-AdapterOutputFields([string]$SourceText) {
  @([regex]::Matches($SourceText, '\\"([a-zA-Z_][a-zA-Z0-9_]*)\\":') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}

function Invoke-AdapterOutputCheck([string]$Root) {
  $issues = @()
  $adapters = @{ "openai"="openai"; "messages"="messages"; "responses"="responses"; "gemini"="gemini" }
  foreach ($entry in $adapters.GetEnumerator()) {
    $dir = Join-Path (Join-Path (Join-Path $Root "src") "provider") $entry.Key
    $file = Join-Path $dir "request_encode.mbt"
    if (-not (Test-Path -LiteralPath $file)) { continue }
    $src = Get-Content -Raw -Encoding UTF8 $file
    $expected = @(Get-AdapterExpectedFields $entry.Value)
    $actual = @(Get-AdapterOutputFields $src)
    $unknown = @($actual | Where-Object { $expected -notcontains $_ } | Sort-Object)
    if ($unknown.Count -gt 0) {
      $issues += New-Issue "adapter_field" ("provider/" + $entry.Key + "/request_encode.mbt") ($unknown -join ",") ($actual -join ",") "JSON field(s) emitted by adapter are not in the target protocol field set"
    }
  }
  $issues
}

function Invoke-Check($Schema, [string]$SchemaText, [string]$SourceText) {
  $issues = @()
  $expectedVersions = @(Get-SchemaVersions $SchemaText)
  $actualVersions = @(Get-SourceVersions $SourceText)
  if ($expectedVersions.Count -ne 1) {
    $issues += New-Issue "version" "schema" "one version const" ($expectedVersions -join ",") "schema_version constants are ambiguous"
  } elseif (($expectedVersions -join ",") -ne ($actualVersions -join ",")) {
    $issues += New-Issue "version" "src/lux" ($expectedVersions -join ",") ($actualVersions -join ",") "production schema_version literals differ"
  }

  $structs = Get-SourceStructs $SourceText
  $aliases = @{ "LucentAnnotation.ref"="reference"; "LucentToolUse.arguments"="arguments_json"; "LucentAgentAction.arguments"="arguments_json"; "LucentTool.parameters"="parameters_json" }
  $skip = @("LucentContent", "LucentMediaSource", "LucentStreamEvent")
  foreach ($entry in (Get-RequiredFields $Schema).GetEnumerator()) {
    $definition = $entry.Key
    $fields = $structs[$definition]
    if ($null -eq $fields) {
      if ($skip -notcontains $definition) { $issues += New-Issue "required" $definition "source struct" "missing" "schema definition has no matching production struct" }
      continue
    }
    foreach ($field in $entry.Value) {
      $aliasKey = "$definition.$field"
      $sourceField = if ($aliases.ContainsKey($aliasKey)) { $aliases[$aliasKey] } else { $field }
      if ($fields -notcontains $sourceField) { $issues += New-Issue "required" $aliasKey $sourceField ($fields -join ",") "required schema field is absent from source struct" }
    }
  }

  $enums = Get-SourceEnums $SourceText
  foreach ($entry in (Get-SchemaEnumValues $Schema).GetEnumerator()) {
    $variants = $enums[$entry.Key]
    if ($null -eq $variants) { $issues += New-Issue "enum" $entry.Key ($entry.Value -join ",") "missing" "schema enum has no matching source enum"; continue }
    $actual = @($variants | Where-Object { $_ -ne "Native" } | ForEach-Object { if ($entry.Key -eq "SupportLevel" -and $_ -eq "Absent") { "none" } else { Convert-ToWireName $_ } })
    $missing = @($entry.Value | Where-Object { $actual -notcontains $_ })
    if ($missing.Count -gt 0) { $issues += New-Issue "enum" $entry.Key ($missing -join ",") ($actual -join ",") "schema enum values are not represented by source constructors" }
  }

  $events = Get-StreamEvents $SchemaText $SourceText
  if (($events.Expected -join ",") -ne ($events.Actual -join ",")) { $issues += New-Issue "stream_event" "LucentStreamEvent" ($events.Expected -join ",") ($events.Actual -join ",") "stream event discriminators differ" }
  $issues
}

if ($SelfTest) {
  $mutated = $schemaText | ConvertFrom-Json
  $mutated.definitions.LucentRole.enum += "deliberate_drift"
  $mutated.definitions.LucentResponse.required += "deliberate_required_drift"
  $mutated.definitions.LucentStreamEvent.oneOf += [pscustomobject]@{ type="object"; properties=[pscustomobject]@{ event=[pscustomobject]@{ const="deliberate_event_drift" } }; required=@("event") }
  $mutated.definitions.LucentRequest.properties.schema_version.const = "v999"
  $mutatedText = $mutated | ConvertTo-Json -Depth 40 -Compress
  $found = @(Invoke-Check $mutated $mutatedText $source).Category | Select-Object -Unique
  $needed = @("version", "required", "enum", "stream_event")
  $missing = @($needed | Where-Object { $found -notcontains $_ })
  if ($missing.Count -gt 0) { Write-Error ("self-test did not detect: " + ($missing -join ", ")); exit 1 }
  # adapter 输出侧：在 openai 编码器样本中注入未知字段，必须被检出
  $adapterSrc = Get-Content -Raw -Encoding UTF8 (Join-Path (Join-Path (Join-Path $Root "src") "provider/openai") "request_encode.mbt")
  $injected = $adapterSrc.Replace('"\"model\":\""', '"\"model\":\"" + ",\"deliberate_adapter_field\":"')
  $adapterExpected = @(Get-AdapterExpectedFields "openai")
  $adapterActual = @(Get-AdapterOutputFields $injected)
  $adapterUnknown = @($adapterActual | Where-Object { $adapterExpected -notcontains $_ })
  if ($adapterUnknown -notcontains "deliberate_adapter_field") { Write-Error "self-test did not detect injected adapter field"; exit 1 }
  Write-Output "self-test: PASS (version, required, enum, stream_event, adapter_field)"
  exit 0
}

$issues = @(Invoke-Check $schema $schemaText $source)
$issues += @(Invoke-AdapterOutputCheck $Root)
$mode = if ($Strict) { "strict" } else { "report" }
Write-Output "schema drift checker (mode=$mode)"
if ($issues.Count -eq 0) { Write-Output "PASS: schema, production Lux IR declarations and adapter output fields are aligned"; exit 0 }
foreach ($issue in $issues) { Write-Output ("[$($issue.Category)] $($issue.Location): $($issue.Message); expected=$($issue.Expected); actual=$($issue.Actual)") }
Write-Output "Found $($issues.Count) drift issue(s)."
if ($Strict) { exit 1 }
exit 0