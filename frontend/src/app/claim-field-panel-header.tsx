interface ClaimFieldPanelHeaderProps {
  title: string;
  onClose: () => void;
}

export function ClaimFieldPanelHeader({ title, onClose }: ClaimFieldPanelHeaderProps) {
  return (
    <header className="editor-header">
      <div>
        <span className="eyebrow">Claim field configuration</span>
        <h2 id="editor-title">{title}</h2>
      </div>
      <button className="icon-button" type="button" onClick={onClose} aria-label="Close">
        X
      </button>
    </header>
  );
}
