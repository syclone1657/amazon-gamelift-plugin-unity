// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEngine;

/// <summary>
/// Headless build script for the Traxion dedicated server.
///
/// Invoked by <c>build-traxion-server.ps1</c> via:
///   Unity.exe -batchmode -quit -executeMethod TraxionServerBuildScript.Build
///
/// Optional command-line overrides (passed after --)
///   -outputPath &lt;path&gt;   Where to write the server binary
///                         Default: &lt;project&gt;/Builds/TraxionServer/TraxionServer
/// </summary>
public static class TraxionServerBuildScript
{
    private const string DefaultOutputPath = "Builds/TraxionServer/TraxionServer";

    // Scenes that make up the server build.
    // Update these paths once you have created the Traxion scenes in the Editor.
    private static readonly string[] ServerScenes =
    {
        "Assets/Scenes/BootstrapScene.unity",
        "Assets/Scenes/GameScene.unity",
    };

    // ── Entry point ───────────────────────────────────────────────────────────

    /// <summary>Called by Unity in batch mode.</summary>
    public static void Build()
    {
        string outputPath = GetArgument("-outputPath") ?? DefaultOutputPath;
        BuildServer(outputPath);
    }

    /// <summary>Also available from the Unity menu for manual builds.</summary>
    [MenuItem("Amazon GameLift/Traxion/Build Server (Linux x64)", priority = 9200)]
    public static void BuildFromMenu()
    {
        string outputPath = EditorUtility.SaveFolderPanel(
            "Choose server output folder",
            "Builds/TraxionServer",
            "") + "/TraxionServer";

        if (string.IsNullOrEmpty(outputPath)) return;
        BuildServer(outputPath);
    }

    // ── Core build logic ──────────────────────────────────────────────────────

    private static void BuildServer(string outputPath)
    {
        Debug.Log($"[Traxion] Building dedicated server to: {outputPath}");

        // Ensure output directory exists
        string dir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            Directory.CreateDirectory(dir);

        // Verify scenes exist before attempting build
        foreach (string scene in ServerScenes)
        {
            if (!File.Exists(scene))
            {
                string msg = $"[Traxion] Scene not found: {scene}\n" +
                             "Create your scenes in the Unity Editor first, then re-run this build.";
                Debug.LogError(msg);
                if (Application.isBatchMode) EditorApplication.Exit(1);
                return;
            }
        }

        var buildOptions = new BuildPlayerOptions
        {
            scenes           = ServerScenes,
            locationPathName = outputPath,
            target           = BuildTarget.StandaloneLinux64,
            subtarget        = (int)StandaloneBuildSubtarget.Server,
            options          = BuildOptions.None,
        };

        // Ensure UNITY_SERVER define is present for the server named target
        var serverTarget = NamedBuildTarget.Server;
        string defines   = PlayerSettings.GetScriptingDefineSymbols(serverTarget);
        if (!defines.Contains("UNITY_SERVER"))
        {
            PlayerSettings.SetScriptingDefineSymbols(serverTarget,
                string.IsNullOrEmpty(defines) ? "UNITY_SERVER" : defines + ";UNITY_SERVER");
        }

        var report = BuildPipeline.BuildPlayer(buildOptions);
        var summary = report.summary;

        if (summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded)
        {
            Debug.Log($"[Traxion] Server build succeeded — {summary.totalSize / 1024 / 1024} MB " +
                      $"at {outputPath}");
            if (Application.isBatchMode) EditorApplication.Exit(0);
        }
        else
        {
            Debug.LogError($"[Traxion] Server build FAILED: {summary.result} " +
                           $"({summary.totalErrors} errors)");
            if (Application.isBatchMode) EditorApplication.Exit(1);
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// <summary>Read a named argument from the Unity command line (after --).</summary>
    private static string GetArgument(string name)
    {
        string[] args = Environment.GetCommandLineArgs();
        for (int i = 0; i < args.Length - 1; i++)
            if (args[i].Equals(name, StringComparison.OrdinalIgnoreCase))
                return args[i + 1];
        return null;
    }
}
