import { useId } from "react";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Label } from "@/components/ui/label";
import { LEVEL_LABELS } from "@/utils/constants";
import { cn } from "@/lib/utils";

interface LevelRadioProps {
  value: number | null; // null = nothing chosen yet
  onChange: (level: number) => void;
  disabled?: boolean;
  className?: string;
}

export default function LevelRadio({ value, onChange, disabled, className }: LevelRadioProps) {
  // Ids unique to this picker: a label activates the FIRST element with its id, so shared
  // "level-2" ids made a click on the second skill change the first one (audit F33).
  const idPrefix = useId();

  return (
    <RadioGroup
      value={value === null ? "" : String(value)}
      onValueChange={(v) => onChange(Number(v))}
      disabled={disabled}
      className={cn("flex items-center gap-3", className)}
    >
      {[1, 2, 3, 4, 5].map((level) => (
        <div key={level} className="flex items-center gap-1">
          <RadioGroupItem value={String(level)} id={`${idPrefix}-level-${level}`} />
          <Label htmlFor={`${idPrefix}-level-${level}`} className="cursor-pointer font-normal">
            {LEVEL_LABELS[level]}
          </Label>
        </div>
      ))}
    </RadioGroup>
  );
}
