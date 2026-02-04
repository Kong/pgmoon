local create_client_first
create_client_first = function(token, extra_params)
  local params = extra_params or { }
  local gs2_header = "n,,"
  local auth_param = "\1auth=Bearer " .. token
  local extra = ""
  for key, value in pairs(params) do
    extra = extra .. "\1" .. key .. "=" .. value
  end
  return gs2_header .. auth_param .. extra .. "\1\1"
end
local validate_token
validate_token = function(token)
  if not (token and type(token) == "string" and #token > 0) then
    return false, "Invalid OAuth token: token must be a non-empty string"
  end
  return true
end
return {
  create_client_first = create_client_first,
  validate_token = validate_token
}
