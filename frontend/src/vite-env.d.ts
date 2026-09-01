/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_ENABLE_TECHNICAL_DETAILS?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
