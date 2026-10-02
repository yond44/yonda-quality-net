import { Button } from "@/components/ui/button";
import { ChevronLeft, ChevronRight } from "lucide-react";

interface PagerProps {
  page: number;
  totalPages: number;
  onChange: (page: number) => void;
}

// Previous / Next controls for a list the API returns one page at a time. Without them,
// everything past the first page was unreachable in the app (audit F35).
// Shows nothing when the whole list fits on one page.
export default function Pager({ page, totalPages, onChange }: PagerProps) {
  if (totalPages <= 1) return null;

  return (
    <nav aria-label="Pages" className="flex items-center justify-between pt-2 text-sm">
      <Button variant="outline" size="sm" onClick={() => onChange(page - 1)} disabled={page <= 1}>
        <ChevronLeft className="h-4 w-4 mr-1" /> Previous
      </Button>
      <span className="text-muted-foreground">
        Page {page} of {totalPages}
      </span>
      <Button variant="outline" size="sm" onClick={() => onChange(page + 1)} disabled={page >= totalPages}>
        Next <ChevronRight className="h-4 w-4 ml-1" />
      </Button>
    </nav>
  );
}
