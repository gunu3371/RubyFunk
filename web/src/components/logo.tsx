import { cn } from "@/lib/utils";
import { BrandMark } from "./brand-mark";
import { Wordmark } from "./wordmark";

// The wrapper width scales the mark and wordmark together.
export function Logo({ className }: { className?: string }) {
	return (
		<div className={cn("relative inline-block", className)}>
			<BrandMark className="absolute left-0 top-0 w-[24%] -translate-x-[55%] -translate-y-[58%] drop-shadow-[0_4px_24px_rgba(196,18,66,0.45)]" />
			<Wordmark className="block h-auto w-full" />
		</div>
	);
}

export default Logo;
