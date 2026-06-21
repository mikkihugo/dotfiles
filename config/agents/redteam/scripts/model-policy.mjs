export const FORBIDDEN_MODEL_POLICY_KEYS = [
  "roster",
  "backend_models",
  "lineage_representatives",
  "model_lineages",
]

const ALLOWED_MODEL_PARAM_KEYS = new Set([
  "base_url",
  "protocol",
  "temperature",
  "thinking_effort",
  "reasoning_effort",
  "adaptive_thinking",
])

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function requireStringArray(value, path, errors, { allowEmpty = false } = {}) {
  if (!Array.isArray(value)) {
    errors.push(`${path} must be an array`)
    return
  }
  if (!allowEmpty && value.length === 0) errors.push(`${path} must not be empty`)
  value.forEach((entry, index) => {
    if (typeof entry !== "string" || entry.length === 0) errors.push(`${path}[${index}] must be a non-empty string`)
  })
}

function requireScalarArray(value, path, errors, { allowEmpty = false } = {}) {
  if (!Array.isArray(value)) {
    errors.push(`${path} must be an array`)
    return
  }
  if (!allowEmpty && value.length === 0) errors.push(`${path} must not be empty`)
  value.forEach((entry, index) => {
    const type = typeof entry
    if ((type !== "string" && type !== "number" && type !== "boolean") || entry === "") {
      errors.push(`${path}[${index}] must be a scalar`)
    }
  })
}

function requireStringMap(value, path, errors, validKeys = null) {
  if (!isRecord(value)) {
    errors.push(`${path} must be an object`)
    return
  }
  for (const [key, reason] of Object.entries(value)) {
    if (validKeys && !validKeys.includes(key)) errors.push(`${path}.${key} has no matching lineage`)
    if (typeof reason !== "string" || reason.length === 0) errors.push(`${path}.${key} must be a non-empty string reason`)
  }
}

export function validateModelsPolicy(cfg) {
  const errors = []
  if (!isRecord(cfg)) return { ok: false, errors: ["models policy must be an object"], lineages: [] }

  for (const key of FORBIDDEN_MODEL_POLICY_KEYS) {
    if (Object.hasOwn(cfg, key)) errors.push(`${key} is forbidden; concrete model ids are discovered live`)
  }

  if (!isRecord(cfg.lineages)) errors.push("lineages must be an object")
  if (!isRecord(cfg.lineage_provider_seeds)) errors.push("lineage_provider_seeds must be an object")

  const lineages = Object.keys(isRecord(cfg.lineages) ? cfg.lineages : {})
  const seedLineages = Object.keys(isRecord(cfg.lineage_provider_seeds) ? cfg.lineage_provider_seeds : {})
  if (lineages.length === 0) errors.push("lineages must not be empty")
  if (seedLineages.length === 0) errors.push("lineage_provider_seeds must not be empty")

  for (const lineage of lineages) {
    if (!seedLineages.includes(lineage)) errors.push(`lineage_provider_seeds.${lineage} is missing`)
  }
  for (const lineage of seedLineages) {
    if (!lineages.includes(lineage)) errors.push(`lineages.${lineage} is missing`)
    requireStringArray(cfg.lineage_provider_seeds[lineage], `lineage_provider_seeds.${lineage}`, errors)
  }

  if (cfg.provider_priority !== undefined) {
    requireStringArray(cfg.provider_priority, "provider_priority", errors, { allowEmpty: true })
  }

  if (cfg.direct_provider_by_lineage !== undefined) {
    if (!isRecord(cfg.direct_provider_by_lineage)) errors.push("direct_provider_by_lineage must be an object")
    else {
      for (const [lineage, provider] of Object.entries(cfg.direct_provider_by_lineage)) {
        if (!lineages.includes(lineage)) errors.push(`direct_provider_by_lineage.${lineage} has no matching lineage`)
        if (typeof provider !== "string" || provider.length === 0) {
          errors.push(`direct_provider_by_lineage.${lineage} must be a non-empty string`)
        }
      }
    }
  }

  if (cfg.free !== undefined) requireStringArray(cfg.free, "free", errors, { allowEmpty: true })

  if (cfg.disabled_lineages !== undefined) requireStringMap(cfg.disabled_lineages, "disabled_lineages", errors, lineages)
  if (cfg.deprioritized_lineages !== undefined) requireStringMap(cfg.deprioritized_lineages, "deprioritized_lineages", errors, lineages)
  if (cfg.disabled_models !== undefined) requireStringMap(cfg.disabled_models, "disabled_models", errors)

  if (!isRecord(cfg.model_params)) errors.push("model_params must be an object")
  else {
    for (const [modelRef, params] of Object.entries(cfg.model_params)) {
      if (!isRecord(params)) {
        errors.push(`model_params.${modelRef} must be an object`)
        continue
      }
      for (const key of Object.keys(params)) {
        if (!ALLOWED_MODEL_PARAM_KEYS.has(key)) errors.push(`model_params.${modelRef}.${key} is not allowed`)
      }
      if (params.temperature !== undefined) requireScalarArray(params.temperature, `model_params.${modelRef}.temperature`, errors)
      for (const key of ["thinking_effort", "reasoning_effort"]) {
        if (params[key] !== undefined) requireStringArray(params[key], `model_params.${modelRef}.${key}`, errors)
      }
      if (params.protocol !== undefined && !["openai", "anthropic", "google"].includes(params.protocol)) {
        errors.push(`model_params.${modelRef}.protocol must be openai, anthropic, or google`)
      }
      if (params.base_url !== undefined && typeof params.base_url !== "string") {
        errors.push(`model_params.${modelRef}.base_url must be a string`)
      }
      if (params.adaptive_thinking !== undefined && typeof params.adaptive_thinking !== "boolean") {
        errors.push(`model_params.${modelRef}.adaptive_thinking must be boolean`)
      }
    }
  }

  return { ok: errors.length === 0, errors, lineages: seedLineages }
}
