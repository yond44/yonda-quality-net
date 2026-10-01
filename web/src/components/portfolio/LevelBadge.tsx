import { LEVEL_LABELS, LEVEL_BADGE_CLASSES, LEVEL_DESCRIPTIONS } from "@/utils/constants";
import { cn } from "@/lib/utils";

interface LevelBadgeProps {
  level: number | null; // null = not assessed (no evidence in the interview)
  size?: "sm" | "md";
  className?: string;
}

export default function LevelBadge({ level, size = "md", className }: LevelBadgeProps) {
  // A skill with no evidence has no level: say so, never show a made-up one (audit F28).
  if (level === null) {
    return (
      <div
        className={cn(
          "inline-flex items-center justify-center rounded font-medium border border-dashed text-muted-foreground",
          size === "md" ? "px-3 py-2 min-w-14 text-xs" : "px-2 py-1 min-w-10 text-[11px]",
          className
        )}
      >
        Not assessed
      </div>
    );
  }

  return (
    <div
      className={cn(
        "inline-flex flex-col items-center justify-center rounded font-semibold",
        size === "md" ? "px-3 py-2 min-w-14 text-base" : "px-2 py-1 min-w-10 text-sm",
        LEVEL_BADGE_CLASSES[level],
        className
      )}
    >
      <span>{LEVEL_LABELS[level]}</span>
      {size === "md" && (
        <span className="text-[10px] font-normal opacity-70">{LEVEL_DESCRIPTIONS[level]}</span>
      )}
    </div>
  );
}
