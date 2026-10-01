import { createTypeScriptImportResolver } from "eslint-import-resolver-typescript";
import globals from "globals";
import importX from "eslint-plugin-import-x";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["lib/**"] },
  importX.flatConfigs.errors,
  importX.flatConfigs.warnings,
  importX.flatConfigs.typescript,
  {
    files: ["src/**/*.ts"],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
      globals: { ...globals.node, ...globals.browser },
    },
    plugins: { "@typescript-eslint": tseslint.plugin },
    settings: {
      "import-x/resolver-next": [createTypeScriptImportResolver()],
    },
    rules: {
      "@typescript-eslint/adjacent-overload-signatures": "error",
      "@typescript-eslint/no-empty-function": "error",
      "@typescript-eslint/no-empty-object-type": "warn",
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-namespace": "error",
      "@typescript-eslint/no-unnecessary-type-assertion": "error",
      "@typescript-eslint/prefer-for-of": "warn",
      "@typescript-eslint/triple-slash-reference": "error",
      "@typescript-eslint/unified-signatures": "warn",
      "comma-dangle": ["error", "always-multiline"],
      "constructor-super": "error",
      eqeqeq: ["warn", "always"],
      "import-x/no-deprecated": "warn",
      "import-x/no-extraneous-dependencies": "error",
      "import-x/no-unassigned-import": "warn",
      "no-cond-assign": "error",
      "no-duplicate-case": "error",
      "no-duplicate-imports": "error",
      "no-empty": ["error", { allowEmptyCatch: true }],
      "no-invalid-this": "error",
      "no-new-wrappers": "error",
      "no-param-reassign": "error",
      "no-redeclare": "error",
      "no-sequences": "error",
      "no-shadow": ["error", { hoist: "all" }],
      "no-throw-literal": "error",
      "no-unsafe-finally": "error",
      "no-unused-labels": "error",
      "no-var": "warn",
      "no-void": "error",
      "prefer-const": "warn",
    },
  },
);
