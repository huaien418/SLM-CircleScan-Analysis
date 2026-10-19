function requireVariables(tableValue, requiredNames, description)
%REQUIREVARIABLES Require named variables in a table.

missing = setdiff(string(requiredNames), string(tableValue.Properties.VariableNames));
if ~isempty(missing)
    error('%s is missing variables: %s', description, strjoin(missing, ', '));
end
end

