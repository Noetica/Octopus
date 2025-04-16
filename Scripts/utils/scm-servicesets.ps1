<#
.SYNOPSIS
    Defines service sets.
.DESCRIPTION
    A hashtable containing service sets for "Synthesys" and "VoicePlatform".
    The "All" set is automatically created as a union of both.
#>
$ServiceSets = @{
    "Synthesys"     = @(
        "Synthesys",
        "Synthesys.Service (Default)",
        "Synthesys.Services.Tenant General (Events)",
        "Synthesys.Services.Tenant General (Default)",
        "Synthesys.Services.Tenant General (AgentDiary)",
        "Synthesys.Services.Tenant General (Entity)",
        "Synthesys.Services.Tenant General (FileUpload)",
        "Synthesys.Services.Tenant General (ImprovedEntity)",
        "Synthesys.Services.Tenant General (Outputs)",
        "Synthesys.Services.Tenant General (Webserver)",
        "Synthesys.Services.Tenant General (UserManagement)",
        "Synthesys.Services.Tenant General (WorkspaceManagement)"
    )
    "VoicePlatform" = @(
        "Noetica DSP",
        # "Noetica Voice Platform-EventLogger", # Disabled on all SaaS platforms
        "Noetica Voice Platform-XChange",
        "Noetica Voice Platform-SwitchInterface",
        "Noetica Voice Platform-ACD",
        "Noetica Voice Platform-Compressor",
        "Noetica.Services.Service (Setup)",
        "Noetica Voice Platform"
    )
}

# Combine the two sets for the "All" target.
$ServiceSets["All"] = $ServiceSets["Synthesys"] + $ServiceSets["VoicePlatform"]
