{
  lib,
  config,
  flake-parts-lib,
  ...
}: let
  inherit (lib) mkOption types;
  inherit
    (flake-parts-lib)
    mkPerSystemOption
    ;
in {
  options = {
    perSystem = mkPerSystemOption ({
      system,
      config,
      pkgs,
      ...
    }: {
      options.scripts = {
        src = mkOption {
          type = types.path;
          description = "The source directory for all scripts";
        };
        scripts = mkOption {
          type = types.lazyAttrsOf (types.submodule {
            options = {
              deps = mkOption {
                type = types.listOf types.package;
                default = [];
              };
              substitutions = mkOption {
                type = types.attrsOf types.str;
                default = {};
              };
            };
          });
          default = {};
          description = ''
            Define scripts using the syntax: scripts.scripts.scriptName = {...}
            Each script can have the following options:
            - deps: A list of package dependencies for the script (default: [])
            - substitutions: An attribute set of string substitutions to apply to the script (default: {})
            The script source file should be located in the directory specified by the 'src' option,
            with the filename matching the script name and a '.sh' extension.
          '';
        };
      };
      config = {
        packages =
          lib.mapAttrs (
            attrName: scriptConfig: let
              script = {
                deps ? [],
                substitutions ? {},
              }: let
                file =
                  (pkgs.writeScriptBin attrName (builtins.readFile (pkgs.substituteAll ({
                      src = "${config.scripts.src}/${attrName}.sh";
                    }
                    // substitutions))))
                  .overrideAttrs (old: {
                    buildCommand = "${old.buildCommand}\n patchShebangs $out";
                  });
                args =
                  map (p: "--prefix PATH : ${p}/bin") deps;
              in
                pkgs.runCommandLocal attrName
                {
                  f = "${file}/bin/${attrName}";
                  buildInputs = [pkgs.makeWrapper];
                  inherit attrName;
                }
                ''
                  makeWrapper "$f" "$out/bin/${attrName}" ${toString args}
                '';
            in
              script scriptConfig
          )
          config.scripts.scripts;

        apps =
          lib.mapAttrs (
            name: scriptConfig: let
              drv = config.packages.${name};
            in {
              type = "app";
              program = "${drv}/bin/${drv.name}";
            }
          )
          config.scripts.scripts;
      };
    });
  };
  # the extra parameter before the module make this module behave like an
  # anonymous module, so we need to manually identify the file, for better
  # error messages, docs, and deduplication.
  _file = __curPos.file;
}
